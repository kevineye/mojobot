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
has 'token';
has 'channel_id';
has rtm => sub { AnyEvent::SlackRTM->new(shift->token) };
has log => sub { Mojo::Log->new };
has ws => sub { WebService::Slack::WebApi->new(token => shift->token) };
has ua => sub { Mojo::UserAgent->new->max_redirects(3) };
has 'icon';
has post_as_user => 1;

# TODO responses should go to channel where triggered when possible
# TODO fix up message updates (provide message ref object with update method)

sub new {
    my $self = shift->SUPER::new(@_);
    $self->channel($self->{channel}) if $self->{channel};

    my $rtm = $self->rtm;

    $rtm->on('hello' => sub {
        $self->log->info('connected to channel ' . $self->channel . ' with token ' . $self->token);

        Mojo::IOLoop->recurring(60 => sub {
            $self->log->debug('ping');
            $rtm->ping;
        });

        $self->emit('start');
    });

    $rtm->on('message' => sub {
        my $message = Bot::Message->new(bot => $self, %{$_[1]});
        $self->log->debug($message->text ? '> ' . $message->text : 'received message');
        $self->emit(message => $message);
        my $user = $self->user($message->user);
        if ($message->type eq "message" and !$message->subtype and $user and not $user->{is_bot}) {
            my $botname = $self->name;
            my $botuser = $self->user($botname);
            $message->{text} =~ s{\@\Q$botuser->{id}\E>}{\@$botname}g if $botname;
            try {
                if ($message->text =~ m{^\s*[\@/]?\Q$botname\E[:,]?\s+}i or $message->text =~ m{\@\Q$botname\E\b}) {
                    $self->emit(respond => $message);
                } else {
                    $self->emit(hear => $message);
                }
            } catch {
                $self->log->error($_);
            };
        }
    });

    $rtm->on('finish' => sub {
        $self->log->info('shutting down');
        $self->emit('finish');
        Mojo::IOLoop->stop;
    });

    $rtm->start;
    return $self;
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

sub start {
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
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
    $self->log->debug("< $message");
    $self->ua->post('https://slack.com/api/chat.postMessage', form => {
        token => $self->token,
        channel => $self->channel_id,
        text => $message,
        ($self->post_as_user ? (as_user => 1) : (username => $self->name, icon_url => $self->url)),
    }, sub {
        my (undef, $tx) = @_;
        my $json = $tx->res->json;
        if ($json->{ok}) {
            $cb->($tx->res->json) if $cb;
        } else {
            $self->log->error($json->{error});
        }
    });
}

sub update {
    my ($self, $ref, $message, $cb) = @_;
    $self->log->debug("< $message");
    $self->ua->post('https://slack.com/api/chat.update', form => {
        token => $self->token,
        ts => $ref->{ts},
        channel => $ref->{channel} || $self->channel_id,
        text => $message,
    }, sub {
        my (undef, $tx) = @_;
        my $json = $tx->res->json;
        if ($json->{ok}) {
            $cb->($tx->res->json) if $cb;
        } else {
            $self->log->error($json->{error});
        }
    });
}


package Bot::Message;
use Mojo::Base -base;

has 'text';
has 'tx';
has 'type';
has 'subtype';
has 'channel';
has 'user';
has 'bot';

sub send {
    shift->bot->send(@_);
}

sub reply {
    my ($self, $message, $cb) = @_;
    $self->bot->send($self->bot->user($self->user)->{name} . ': ' . $message, $cb);
}

1;
