#Description
# See if MojoBot knows who you are
#
#Commands
# mojobot [What's | Tell me | Say] my name - MojoBot reaffirms your existence
# mojobot who am i - MojoBot reaffirms your existence.. or not
#
#Comments
# what's my name pattern doesn't seem to be working from slack
#Author(s)
# wfwheel - William Frank Wheeler II
use strict;
use utf8;
use Data::Dumper;

sub {
    my ($robot) = @_;

    my $get_user_name_from = sub {
        my ($msg) = shift;
        return undef if not( $msg->can('user') and $msg->user() );
        my $user = $robot->io->ws->users->info( user => $msg->user() );
        $robot->log->debug( Dumper($user) );
        return undef if not $user->{ok};
        return $user->{user}->{real_name}
            ? $user->{user}->{real_name}
            : $user->{user}->{name};
    };

    my %responses = (
        q/what is/ => 'Who are any of us really?',
        q/what's/  => 'Who are any of us really?',
        q/tell me/ => 'How am I supposed to know',
        say        => 'Sorry, no clue',
    );

    $robot->respond(
        qr/(What( is|'s)?|Tell me|Say) my name/i,
        sub {
            my ( $msg, @matches ) = @_;
            my $verb = shift @matches;
            my $name = $get_user_name_from->($msg);
            if ($name) {
                $msg->send($name);
            }
            else {
                $msg->send( $responses{$verb} );
            }
        }
    );

    $robot->respond(
        qr/Who am [iI]/i,
        sub {
            my ($msg)           = @_;
            my @responses_array = values %responses;
            my $name            = $get_user_name_from->($msg);
            if ($name) {
                $msg->send($name);
            }
            else {
                $msg->send( $responses_array[ rand @responses_array ] );
            }

        }
    );

};
