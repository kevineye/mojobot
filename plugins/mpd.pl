# Description:
#   Control remote MPD music player daemon
#
# Dependencies:
#   mpc command line executable
#
# Configuration:
#   MOJOBOT_MPC - mpc command
#
# Commands:
#   mpc [status]
#   mpc play
#   mpc pause
#   mpc next
#   mpc prev
#   mpc help

use strict;

sub {
    my ($robot) = @_;

    $robot->respond(qr/mpc($| .*)/i, sub {
        my ($msg, $cmd) = @_;
        $msg->send(mpc($cmd));
    });

    my $mpc_cmd;
    sub mpc {
        my ($cmd) = @_;
        $mpc_cmd ||= find_mpc();
        return scalar qx{$mpc_cmd $cmd 2>&1};
    }

    sub find_mpc {
        return $ENV{MOJOBOT_MPC} if $ENV{MOJOBOT_MPC};

        my $which_mpc = qx{which mpc};
        chomp $which_mpc;
        return $which_mpc if $which_mpc;

        my $which_docker = qx{which docker};
        chomp $which_docker;
        system "$which_docker pull jess/mpd 2>/dev/null >/dev/null &";
        return "$which_docker run --rm --net host --entrypoint mpc jess/mpd";
    }

};
