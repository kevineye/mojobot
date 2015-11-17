# Description:
#   Count as a demonstration of updating a past message.
#
# Commands:
#   hubot count - Count to 10.
#   hubot count to # - Count to some other number

use strict;

sub {
    my ($bot) = @_;

    $bot->respond(qr/count(?: to (\d+))?/i => sub {
        my ($m, $count) = @_;
        $count ||= 10;
        my $counter = 0;
        $m->send("counting: $counter", sub {
            my ($ref) = @_;
            my $update;
            $update = sub {
                $bot->update($ref, 'counting: ' . ++$counter);
                Mojo::IOLoop->timer(0.5 => $update) if $counter < $count;
            };
            Mojo::IOLoop->timer(0.5 => $update);
        });
    });

};
