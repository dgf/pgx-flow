use strict;
use warnings;
use Data::Dumper;
use DBI;
use IO::Select;
use JSON::XS;
use Switch;

# configuration
my %cfg = (
  dbName => 'flow_check',
  dbUser => 'dgf',
  dbPass => undef
);

# define commands
my $commands = {
  mail => \&mail,
  http => \&http
};

# SMTP client
sub mail {
  my $uid = $_[0];
  my $config  = $_[1];
  warn "TBD send mail $uid to $config->{'to'}: '$config->{'subject'}'";
  return {
    status => 'ok',
    remote => '127.0.0.1'
  };
}

# HTTP client
use LWP::UserAgent;
my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });

sub http {
  my $uid = $_[0];
  my $config  = $_[1];
  warn "http $config->{method} $config->{url}";
  my $res = undef;
  switch ($config->{method}) {
    case /get/i { $res = $ua->get($config->{url}); }
    case /post/i { $res = $ua->post($config->{url}, $config->{data}); }
  }
  if (not $res) {
    return {
      code => 500,
      body => "unsupported method: $config->{method}"
    };
  } else {
    return {
      code => $res->{'_rc'},
      body => $res->{'_content'}
    };
  }
}

# connect database channel
my $db = DBI->connect('dbi:Pg:dbname=' . $cfg{dbName}, $cfg{dbUser}, $cfg{dbPass}, {
  RaiseError => 1,
  AutoCommit => 1
});
my $selectCall = $db->prepare(qq{
  SELECT request FROM flow.call WHERE uid = :uid AND status = 'new'
});
my $startCall = $db->prepare(qq{
  UPDATE flow.call SET status = 'open' WHERE uid = :uid
});
my $finishCall = $db->prepare(qq{
  UPDATE flow.call SET status = 'done', response = :response WHERE uid = :uid
});
$db->do('LISTEN call');

# await notify
my $sel=IO::Select->new($db->{pg_socket});
while ($sel->can_read) {

  # read all notifies of one transaction
  while (my $notify = $db->pg_notifies) {

    # decode and validate payload
    my ($name, $pid, $payload) = @$notify;
    my $data  = decode_json($payload);
    my $type = ref $data;
    if ($type ne 'HASH') {
      warn "invalid type: $type";
    } else {

      # find and call command
      my $func = $data->{'func'};
      if (not $func) {
        warn "func reference not found: $payload";
      } else {
        my $command = $commands->{$func};
        if (not $command) {
          warn "unknown func: $payload";
        } else {
          my $uid = $data->{'uid'};
          if (not $uid) {
            warn "call without reference: $payload";
          } else {

            # fetch and validate results
            $selectCall->bind_param(":uid", $uid);
            $selectCall->execute();
            my @row = $selectCall->fetchrow_array();
            if (not @row) {
              warn "request data not found: $payload";
            } elsif (scalar(@row) ne 1){
              warn "invalid row data: " . Dumper(@row);
            } else {

              # call command
              $startCall->bind_param(":uid", $uid);
              $startCall->execute();
              my $response = encode_json($command->($uid, decode_json($row[0])));

              # update response status
              $finishCall->bind_param(":uid", $uid);
              $finishCall->bind_param(":response", $response);
              $finishCall->execute();
            }
          }
        }
      }
    }
  }
};
