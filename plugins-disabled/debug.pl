use strict;
use Mojo::JSON 'to_json';

sub {
    my ($bot) = @_;

    $bot->on(message => sub {
        my (undef, $m) = @_;
        my $data = { %$m };
        delete $data->{bot};
        $bot->log->debug(to_json $data);
        my $user = $bot->user($data->{user});
        $bot->log->debug(to_json $user) if $user;
    });

};
