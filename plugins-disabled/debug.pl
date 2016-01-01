use strict;
use Mojo::JSON 'to_json';

sub {
    my ($bot) = @_;

    $bot->on(message => sub {
        my (undef, $m) = @_;
        my $data = { %$m };
        delete $data->{bot};
        $bot->log->debug('message: ' . to_json $data);
        if ($bot->can('user')) {
            my $user = $bot->user($data->{user});
            $bot->log->debug('from: ' . to_json $user) if $user;
        }
    });

    $bot->on(hear => sub {
        my (undef, $m) = @_;
        my $data = { %$m };
        delete $data->{bot};
        $bot->log->debug('hear: ' . to_json $data);
    });

    $bot->on(respond => sub {
        my (undef, $m) = @_;
        my $data = { %$m };
        delete $data->{bot};
        $bot->log->debug('respond: ' . to_json $data);
    });

    # Mojo::IOLoop->recurring(2 => sub { warn "tick\n" });

};
