package Bot;
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::IOLoop;
use Mojo::Log;
use Mojo::UserAgent;
use EV;
use AnyEvent;
use AnyEvent::SlackRTM;
use Try::Tiny;
use WebService::Slack::WebApi;

has name => 'mojobot';
has log => sub { Mojo::Log->new };
has ua => sub { Mojo::UserAgent->new->max_redirects(3) };

sub new {
    my $self = shift->SUPER::new(@_);
    $self->io(delete $self->{io}) if exists $self->{io};
    return $self;
}

sub start {
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

sub io {
    my $self = shift;
    if (@_) {
        $self->{io} = shift;
        $self->{io}->bot($self);
    }
    $self->{io} ||= Bot::IO::Console->new(io => $self);
    return $self->{io};
}

sub safe_emit {
    my ($self, @args) = @_;
    try {
        $self->emit(@args);
    } catch {
        $self->log->error($_);
    };
}

sub hear {
    my ($self, $pattern, $cb) = @_;
    $self->on('hear', sub {
        my (undef, $message) = @_;
        my $text = $message->text;
        $text =~ s{^\s+|\s+$}{}g;
        if (my @matches = ($text =~ $pattern)) {
            try {
                $cb->($message, @matches);
            } catch {
                $self->log->error($_);
            }
        }
    });
}

sub respond {
    my ($self, $pattern, $cb) = @_;
    $self->on('respond', sub {
        my (undef, $message) = @_;
        my $text = $message->text;
        $text =~ s{^\s+|\s+$}{}g;
        if (my @matches = ($text =~ $pattern)) {
            try {
                $cb->($message, @matches);
            } catch {
                $self->log->error($_);
            }
        }
    });
}

sub load_plugins {
    my $self = shift;
    for my $file (map { glob $_ } @_) {
        try {
            my $cb = do $file;
            $cb->($self);
        } catch {
            $self->log->error("error loading $file: $_");
        }
    }
    return $self;
}

sub send {
    my ($self, $message, $cb) = @_;
    $self->io->send($message, $cb);
}


package Bot::Message;
use Mojo::Base -base;

has 'text';
has 'bot';

sub is_to_bot {
    my ($self) = shift;
    my $botname = $self->bot->name;
    return $self->text =~ m{^\s*[\@/]?\Q$botname\E[:,]?\s+}i || $self->text =~ m{\@\Q$botname\E\b};
}

sub send {
    my ($self, $text, $cb) = @_;
    $self->bot->io->send($text, $cb);
}

sub reply {
    my ($self, $text, $cb) = @_;
    $self->send($text, $cb);
}

sub update {
    my ($self, $new_text, $cb) = @_;
    $self->send($new_text, $cb);
}


package Bot::IO;
use Mojo::Base -base;

sub new {
    my $self = shift->SUPER::new(@_);
    $self->bot(delete $self->{bot}) if exists $self->{bot};
    return $self;
}

sub bot {
    my $self = shift;
    if (@_ and not defined $self->{bot}) {
        $self->{bot} = shift;
        $self->init;
    }
    return $self->{bot};
}

sub init {}


package Bot::IO::Console;
use Mojo::Base 'Bot::IO';

has in => sub { Mojo::IOLoop::Stream->new(\*STDIN)->timeout(0) };

sub init {
    my $self = shift;
    my $stdin = $self->in;
    binmode STDOUT, ':encoding(UTF-8)';

    $stdin->on(read => sub {
        my ($stream, $bytes) = @_;
        $stdin->{line_buffer} .= $bytes;
        while ((my $i = index $stdin->{line_buffer}, "\n") > -1) {
            $stdin->emit(line => substr $stdin->{line_buffer}, 0, $i);
            $stdin->{line_buffer} = substr $stdin->{line_buffer}, $i+1;
        }
    });

    $stdin->on(close => sub {
        my ($stream) = @_;
        $stdin->emit(line => $stdin->{line_buffer}) if defined $stdin->{line_buffer} and length $stdin->{line_buffer};
        $self->bot->safe_emit('finish');
        Mojo::IOLoop->stop;
    });

    $stdin->on(line => sub {
        my ($stream, $line) = @_;
        chomp $line;
        my $message = Bot::Message->new( bot => $self->bot, text => $line );
        $self->bot->safe_emit(message => $message);
        $self->bot->safe_emit(($message->is_to_bot ? 'respond' : 'hear'), $message) if length $message->text;
    });

    Mojo::IOLoop->next_tick(sub {
        $self->bot->safe_emit('start');
    });

    $stdin->start;
}

sub send {
    my ($self, $text, $cb) = @_;
    printf "%s> %s\n", $self->bot->name, $text;
    $cb->(Bot::Message->new(text => $text, bot => $self->bot)) if $cb;
    return $self;
}


package Bot::IO::Slack;
use Mojo::Base 'Bot::IO';

has 'token';
has 'channel_id';
has rtm => sub { AnyEvent::SlackRTM->new(shift->token) };
has ws => sub { WebService::Slack::WebApi->new(token => shift->token) };
has 'icon';
has post_as_user => 1;

sub init {
    my $self = shift;
    $self->channel($self->{channel}) if $self->{channel};

    my $rtm = $self->rtm;

    $rtm->on('hello' => sub {
        $self->bot->log->info('connected to slack channel ' . $self->channel . ' with token ' . $self->token);

        Mojo::IOLoop->recurring(60 => sub {
            $self->bot->log->debug('ping');
            $rtm->ping;
        });

        $self->bot->safe_emit('start');
    });

    $rtm->on(message => sub {
        my $message = Bot::Message::Slack->new(bot => $self->bot, %{$_[1]});
        $self->bot->log->debug($message->text ? '> ' . $message->text : 'received message');
        $self->bot->safe_emit(message => $message);
        if (length $message->text) {
            my $user = $self->user($message->user);
            if ($message->type eq "message" and !$message->subtype and $user and not $user->{is_bot}) {
                $DB::single = 1;
                my $botname = $self->bot->name;
                my $botuser = $self->user($botname);
                $message->{text} =~ s{<\@\Q$botuser->{id}\E>}{\@$botname}g if $botname;
                $self->bot->safe_emit(($message->is_to_bot ? 'respond' : 'hear'), $message);
            }
        }
    });

    $rtm->on('finish' => sub {
        $self->bot->safe_emit('finish');
        Mojo::IOLoop->stop;
    });

    $rtm->start;
}

sub channel {
    my $self = shift;

    my $update = sub {
        $self->{channels} = {
            ( map { $_->{id}, $_, "#$_->{name}", $_ } @{$self->ws->channels->list->{channels} || []} ),
            ( map { $_->{id}, $_, $_->{name}, $_ } @{$self->ws->groups->list->{groups} || []} ),
            ( map { $_->{id}, $_, $_->{user}, $_, '@'.$self->user($_->{user})->{name}, $_ } grep { $_->{user} ne 'USLACKBOT' } @{$self->ws->im->list->{ims} || []} ),
        };
    };

    if (@_) {
        my $c = shift;
        $update->() unless exists $self->{channels} and exists $self->{channels}{$c};
        $self->channel_id($self->{channels}{$c}{id});
    }
    $update->() unless exists $self->{channels} and exists $self->{channels}{$self->channel_id};
    return $self->{channels}{$self->channel_id}{name};
}

sub user {
    my ($self, $user) = @_;
    return unless $user;
    if (not exists $self->{users} or not exists $self->{users}{$user}) {
        $self->{users} = $self->{users} = {
            map { $_->{id}, $_, $_->{name}, $_ } @{$self->ws->users->list->{members} || []}
        };
    }
    return $self->{users}{$user};
}

sub send {
    my ($self, $text, $cb) = @_;
    $self->send_channel($self->channel_id, $text, $cb);
}

sub send_channel {
    my ($self, $channel, $text, $cb) = @_;
    $self->bot->log->debug("< $text");
    $self->bot->ua->post('https://slack.com/api/chat.postMessage', form => {
        token => $self->token,
        channel => $channel,
        text => $text,
        ($self->post_as_user ? (as_user => 1) : (username => $self->name, icon_url => $self->url)),
    }, sub {
        my (undef, $tx) = @_;
        my $json = $tx->res->json;
        if ($json->{ok}) {
            my $message = Bot::Message::Slack->new(bot => $self->bot, channel => $json->{channel}, tx => $tx, %{$json->{message}});
            $cb->($message) if $cb;
        } else {
            $self->bot->log->error($json->{error});
        }
    });
}


package Bot::Message::Slack;
use Mojo::Base 'Bot::Message';

has 'tx';
has 'type';
has 'subtype';
has 'channel';
has 'user';
has 'ts';

sub send {
    my $self = shift;
    $self->bot->io->send_channel($self->channel, @_);
}

sub reply {
    my ($self, $message, $cb) = @_;
    $self->bot->io->send_channel($self->channel, $self->bot->user($self->user)->{name} . ': ' . $message, $cb);
}

sub update {
    my ($self, $new_text, $cb) = @_;
    $self->bot->log->debug("< $new_text");
    $self->bot->ua->post('https://slack.com/api/chat.update', form => {
            token => $self->bot->io->token,
            ts => $self->ts || undef,
            channel => $self->channel || $self->bot->io->channel_id,
            text => $new_text,
        }, sub {
            my (undef, $tx) = @_;
            my $json = $tx->res->json;
            if ($json->{ok}) {
                my $new_message = Bot::Message::Slack->new(bot => $self->bot, channel => $json->{channel}, tx => $tx, %{$json->{message}});
                $cb->($new_message) if $cb;
            } else {
                $self->bot->log->error($json->{error});
            }
        });
}

1;
