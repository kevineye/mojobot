# Description:
#   Control remote MPD music player daemon
#
# Dependencies:
#   mpc command line executable
#
# Configuration:
#   MOJOBOT_MPC_CMD - mpc command
#   MOJOBOT_MPD_HOST - mpc host
#   MOJOBOT_MPD_PORT - mpc port
#   MOJOBOT_MPC_CHANNEL - mpc channel
#
# Commands:
#   mpc [status]
#   mpc play
#   mpc pause
#   mpc next
#   mpc prev
#   mpc help
#
# All commands also respond to "mpd" or "music" instead of "mpc".

use strict;

sub {
    my ($robot) = @_;

    my $this_dir = sub {
        # get calling context, including file path
        my ($package, $file, $line) = caller();

        # separate the path from the file name
        my ($path, $filename) =
            $file =~ m|^(.*)/(.*)$|
            or die "cannot determine script dir";

        return $path;
    };

    my $find_mpc = sub {
        my $cmd = $ENV{MOJOBOT_MPC_CMD};

        unless ($cmd) {
            my $which_mpc = qx{which mpc};
            chomp $which_mpc;
            $cmd = $which_mpc if $which_mpc;
        }

        unless ($cmd) {
            my $builtin = $this_dir->() . "/mpc";
            $cmd = $builtin if -x $builtin;
        }

        if ($cmd) {
            $cmd .= " --host=$ENV{MOJOBOT_MPD_HOST}" if $ENV{MOJOBOT_MPD_HOST};
            $cmd .= " --port=$ENV{MOJOBOT_MPD_PORT}" if $ENV{MOJOBOT_MPD_PORT};
            return $cmd;
        }

        return;
    };

    my $mpc_cmd = $find_mpc->();
    my $mpc = sub {
        my ($cmd) = @_;
        return $mpc_cmd && scalar qx{$mpc_cmd $cmd 2>&1};
    };

    my $working = $mpc->('version') =~ m{mpd version:};

    $robot->log->warn("mpc is not installed or cannot connect to mpd") unless $working;

    my $mpc_handler = sub {
        my ($msg, $cmd) = @_;
        if ($working) {
            my $out = $mpc->($cmd);
            $msg->send($out || 'ok');
        } else {
            $msg->send("Sorry, mpc is not installed or cannot connect to mpd.");
        }
    };
    $robot->respond(qr/(?:mp[cd]|music)($| .*)/i, $mpc_handler);
    $robot->hear(qr/^(?:mp[cd]|music)($| .*)/i, $mpc_handler);

    if ($working) {
        $robot->on(start => sub {
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
                    my $msg = $mpc->('status');
                    my ($song, $playpause) = $msg =~ m{^(.*)\n\[(\w+)\]};
                    my $status = $playpause eq 'playing' ? "Playing $song" : $playpause eq 'paused' ? 'Music paused' : 'Music stopped';
                    if ($status ne $last_status) {
                        $last_status = $status;
                        if ($ENV{MOJOBOT_MPC_CHANNEL} and $robot->io->can('send_channel')) {
                            $robot->io->send_channel($ENV{MOJOBOT_MPC_CHANNEL}, $status);
                        } else {
                            $robot->send($status);
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
    }

};
