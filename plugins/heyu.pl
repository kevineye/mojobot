# Description:
#   Control remote MPD music player daemon
#
# Dependencies:
#   mpc command line executable
#
# Configuration:
#   MOJOBOT_HEYU_CMD - heyu command
#   MOJOBOT_HEYU_CHANNEL - channel for heyu announcements
#
# Commands:
#   heyu help
#   heyu macro <label>
#   heyu on|off <house><unit>
#   heyu allon|alloff <house>
#   heyu turn <house><unit> on|off
#   turn all|everything on|off
#   turn <house><unit>|<label> on|off
#   turn on|off all|everything
#   turn on|off <house><unit>|<label>


use strict;

sub {
    my ($robot) = @_;

    my $find_heyu = sub {
        my $cmd = $ENV{MOJOBOT_HEYU_CMD};

        unless ($cmd) {
            my $which_heyu = qx{which heyu};
            chomp $which_heyu;
            $cmd = $which_heyu if $which_heyu;
        }

        return $cmd
    };

    my $heyu_cmd = $find_heyu->();
    my $heyu = sub {
        my ($cmd) = @_;
        return $heyu_cmd && scalar qx{$heyu_cmd $cmd 2>&1};
    };

    my $working = $heyu->('info') =~ m{Heyu version };

    $robot->log->warn("heyu is not installed or cannot connect to hardware interface") unless $working;

    my @working_responses = (
        'working on that…',
        'let me see what I can do…',
        'I’ll get right on that…',
        'just a sec…',
        'coming right up…',
        'hang on…',
    );

    my $heyu_handler = sub {
        my ($msg, $cmd) = @_;
        if ($working) {
            $msg->send($working_responses[rand @working_responses], sub {
                my $m = shift;
                my $out = $heyu->($cmd);
                $m->update($out || 'ok');
            });
        } else {
            $msg->send("Sorry, heyu is not installed or cannot connect to hardware interface.");
        }
    };

    $robot->respond(qr/heyu($| .*)/i, $heyu_handler);

    $robot->hear(qr/^heyu($| .*)/i, $heyu_handler);

    $robot->hear(qr/^turn (\w+) (on|off)$|^turn (on|off) (\w+)$/i, sub {
        my ($msg, $code, $onoff) = @_;
        $code ||= $_[4];
        $onoff ||= $_[3];
        my $cmd;
        if (lc $code eq 'all' or lc $code eq 'everything') {
            $cmd = "macro downstairs_$onoff";
        } else {
            $cmd = "$onoff $code";
        }
        $heyu_handler->($msg, $cmd);
    });


    if ($working) {
        $robot->on(start => sub {
            my $fh;
            my $pid = $heyu_cmd && open $fh, '-|', "$heyu_cmd monitor </dev/null";
            if ($pid) {
                $robot->log->info("connected to heyu using $heyu_cmd");
            } else {
                $robot->log->warn("connection to heyu failed" . ($heyu_cmd ? " ($heyu_cmd)" : "(no command)"));
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
                $robot->log->warn('heyu monitor closed');
            });

            my $last_status = '';
            $in->on(line => sub {
                my ($stream, $line) = @_;
                chomp $line;
                $line = substr $line, 16;
                if (length $line and $line ne 'Monitor started') {
                    if ($ENV{MOJOBOT_HEYU_CHANNEL} and $robot->io->can('send_channel')) {
                        $robot->io->send_channel($ENV{MOJOBOT_HEYU_CHANNEL}, $line);
                    } else {
                        $robot->send($line);
                    }
                }
            });

            $in->start;
        });
    }

};
