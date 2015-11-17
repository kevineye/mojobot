# Description:
#   Pugme is the most important thing in life
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   hubot pug me - Receive a pug
#   hubot pug bomb N - get N pugs

use strict;

sub {
    my ($robot) = @_;

    $robot->respond(qr/pug me/i, sub {
        my ($msg) = @_;
        $robot->ua->get("http://pugme.herokuapp.com/random" => sub {
            my (undef, $tx) = @_;
            $msg->send($tx->res->json->{pug});
        });
    });

    $robot->respond(qr/pug bomb(?: (\d+))?/i, sub {
        my ($msg, $count) = @_;
        $count ||= 5;
        $robot->ua->get("http://pugme.herokuapp.com/bomb?count=$count" => sub {
            my (undef, $tx) = @_;
            $msg->send($_) for @{$tx->res->json->{pugs}};
        });
    });

    $robot->respond(qr/how many pugs are there/i, sub {
        my ($msg) = @_;
        $robot->ua->get("http://pugme.herokuapp.com/count" => sub {
            my (undef, $tx) = @_;
            $msg->send("There are " . $tx->res->json->{pug_count} . " pugs.");
        });
    });

};
