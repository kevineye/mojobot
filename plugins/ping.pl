# Description:
#   Make sure mojobot is still hangin' around.
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   mojobot {ping|hi|hello|hey|yo}
#

use strict;
use utf8;

sub {
    my ($robot) = @_;

    my @response = (
        "hi",
        "hello",
        "how’s it going?",
        "sup?",
        "what’s happenin?",
        "yo!"
    );

    $robot->respond(qr/\bhi|hello|hey|yo\b/i, sub {
        my ($msg) = @_;
        $msg->send($response[rand @response]);
    });

    $robot->respond(qr/\bping\b/i, sub {
        my ($msg) = @_;
        $msg->send('pong');
    });

};
