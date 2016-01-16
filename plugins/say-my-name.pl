#Description
# See if MojoBot knows who you are
#
#Commands
# mojobot [What's | Tell me | Say] my name - MojoBot reaffirms your existence
# mojobot who am i - MojoBot reaffirms your existence.. or not
#Author(s)
# wfwheel - William Frank Wheeler II
use strict;
use utf8;

sub {
    my ($robot) = @_;

    my %responses = (
        q/what's/  => 'Who are any of us really?',
        whats      => 'Who are any of us really?',
        say        => 'How am I supposed to know',
        q/tell me/ => 'Sorry, no clue',
    );

    $robot->respond(
        qr/(What'?s|Tell me|Say) my name/i,
        sub {
            my ( $msg, @matches ) = @_;
            my $verb = shift @matches;
            if ( $msg->can('user') and $msg->user() ) {
                $msg->send( $msg->user() );
            }
            else {
                $msg->send( $responses{$verb} );
            }
        }
    );

    $robot->respond(
        qr/Who am [iI]/i,
        sub {
            my ($msg) = @_;
            my @responses_array = values %responses;
            $msg->send( $responses_array[ rand @responses_array ] );
        }
    );
};
