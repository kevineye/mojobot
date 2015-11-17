use strict;

sub {
    my ($bot) = @_;

    $bot->on(start => sub {
        $bot->send('Hello!');
    });

    $bot->on(finish => sub {
        $bot->send('Goodbye!');
    });

}
