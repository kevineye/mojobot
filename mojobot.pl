#!/usr/bin/perl
use strict;
use FindBin '$RealBin';
use lib "$RealBin/lib";
use Bot;

Bot->new(
        token => shift || $ENV{MOJOBOT_SLACK_TOKEN},
        name => shift || $ENV{MOJOBOT_NAME} || 'mojobot',
        channel => shift || $ENV{MOJOBOT_SLACK_CHANNEL} || '#general',
    )
    ->load_plugins("$RealBin/plugins/*")
    ->start;
