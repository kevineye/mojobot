# Description:
#   Hubot responds any thank message politely. Phrases from:
#   http://www.macmillandictionary.com/thesaurus-category/british/Ways-of-accepting-someone-s-thanks
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   hubot thank[s] [you] - Hubot accepts your thanks
#   thanks hubot - Hubot accepts your thanks
#
# Original author:
#   github.com/delucas
#
# Adapted from:
#   https://github.com/hubot-scripts/hubot-thank-you/blob/master/src/thank-you.coffee

use strict;
use utf8;

sub {
    my ($robot) = @_;

    my @response = (
        "you’re welcome",
        "no problem",
        "not a problem",
        "no problem at all",
        "don’t mention it",
        "it’s no bother",
        "it’s my pleasure",
        "my pleasure",
        "it’s nothing",
        "think nothing of it",
        "no, no. thank you!",
        "sure thing"
    );

    $robot->respond(qr/\bthanks?\b/i, sub {
        my ($msg) = @_;
        $msg->send($response[rand @response]);
    });

    my $name = $robot->name;
    $robot->hear(qr/\bthanks?\b.*\b\Q$name\E\b/i, sub {
        my ($msg) = @_;
        $msg->send($response[rand @response]);
    });

};
