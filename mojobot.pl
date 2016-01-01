#!/usr/bin/perl
use strict;
use FindBin '$RealBin';
use lib "$RealBin/lib";
use Bot;

my $io;

if ($ENV{MOJOBOT_SLACK_TOKEN}) {
    $io = Bot::IO::Slack->new(
        token => shift || $ENV{MOJOBOT_SLACK_TOKEN},
        channel => shift || $ENV{MOJOBOT_SLACK_CHANNEL} || '#general',
    );
} else {
    $io = Bot::IO::Console->new;
}

Bot->new( io => $io, name => shift || $ENV{MOJOBOT_NAME} || 'mojobot' )
    ->load_plugins("$RealBin/plugins/*")
    ->start;
