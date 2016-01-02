# Description:
#   Control remote MPD music player daemon
#
# Dependencies:
#   mpc command line executable
#
# Configuration:
#   MOJOBOT_MPC_CMD - mpc command
#   MOJOBOT_MPC_CHANNEL - mpc channel
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
        my $out = mpc($cmd);
        $msg->send($out) if $out;
    });

    my $mpc_cmd;
    sub mpc {
        my ($cmd) = @_;
        $mpc_cmd ||= find_mpc();
        return $mpc_cmd && scalar qx{$mpc_cmd $cmd 2>&1};
    }

    sub find_mpc {
        return $ENV{MOJOBOT_MPC_CMD} if $ENV{MOJOBOT_MPC_CMD};

        my $which_mpc = qx{which mpc};
        chomp $which_mpc;
        return $which_mpc if $which_mpc;

        my $which_docker = qx{which docker};
        chomp $which_docker ;
        return "$which_docker run --rm --net host --entrypoint mpc jess/mpd";
    }

    $robot->on(start => sub {
        my $mpc_cmd = find_mpc();
        my $fh;
        my $pid = $mpc_cmd && open $fh, '-|', "$mpc_cmd idleloop </dev/null";
        if ($pid) {
            $robot->log->info("connected to mpd using $mpc_cmd");
        } else {
            $robot->log->warn("connection to mpd failed" . ($mpc_cmd ? " ($mpc_cmd)" : "(no command)"));
        }
        my $in = Mojo::IOLoop::Stream->new($fh)->timeout(0);

        $in->on(read => sub {
            my ($stream, $bytes) = @_;
            $in->{line_buffer} .= $bytes;
            while ((my $i = index $in->{line_buffer}, "\n") > -1) {
                $in->emit(line => substr $in->{line_buffer}, 0, $i);
                $in->{line_buffer} = substr $in->{line_buffer}, $i+1;
            }
        });

        $in->on(close => sub {
            my ($stream) = @_;
            $in->emit(line => $in->{line_buffer}) if defined $in->{line_buffer} and length $in->{line_buffer};
            $robot->log->warn('mpd idleloop closed');
        });

        my $last_status = '';
        $in->on(line => sub {
            my ($stream, $line) = @_;
            chomp $line;
            if ($line eq 'player') {
                my $msg = mpc('status');
                my ($song, $playpause) = $msg =~ m{^(.*)\n\[(\w+)\]};
                if ($playpause eq 'playing') {
                    my $status = "Playing $song";
                    if ($status ne $last_status) {
                        $last_status = $status;
                        if ($ENV{MOJOBOT_MPC_CHANNEL} and $robot->io->can('send_channel')) {
                            $robot->io->send_channel($ENV{MOJOBOT_MPC_CHANNEL}, $status);
                        } else {
                            $robot->send($status);
                        }
                    }
                }
            } elsif ($line eq 'output') {
                # ignore
            } elsif ($line eq 'options') {
                # ignore
            } else {
                $robot->log->warn("unknown mpd idleloop message: $line");
            }
        });

        $in->start;
    });

};
