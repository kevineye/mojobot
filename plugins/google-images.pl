# Description:
#   A way to interact with the Google Images API.
#
# Configuration
#   HUBOT_GOOGLE_CSE_KEY - Your Google developer API key
#   HUBOT_GOOGLE_CSE_ID - The ID of your Custom Search Engine
#   HUBOT_MUSTACHIFY_URL - Optional. Allow you to use your own mustachify instance.
#   HUBOT_GOOGLE_IMAGES_HEAR - Optional. If set, bot will respond to any line that begins with "image me" or "animate me" without needing to address the bot directly
#   HUBOT_GOOGLE_SAFE_SEARCH - Optional. Search safety level.
#
# Commands:
#   hubot image me <query> - The Original. Queries Google Images for <query> and returns a random top result.
#   hubot animate me <query> - The same thing as `image me`, except adds a few parameters to try to return an animated GIF instead.
#   hubot mustache me <url> - Adds a mustache to the specified URL.
#   hubot mustache me <query> - Searches Google Images for the specified query and mustaches it.
#
# Adapted from:
#   https://github.com/hubot-scripts/hubot-google-images/blob/master/src/google-images.coffee

use strict;

use Mojo::URL;
use Mojo::Util 'url_escape';

sub {
    my ($robot) = @_;

    $robot->respond(qr/(?:image|img)(?: me)? (.+)/i => sub {
        my ($msg, $query) = @_;
        image_me($robot, $msg, $query, 0, 0, sub {
            my ($url) = @_;
            $msg->send($url);
        });
    });

    $robot->respond(qr/animate(?: me)? (.+)/i => sub {
        my ($msg, $query) = @_;
        image_me($robot, $msg, $query, 1, 0, sub {
            my ($url) = @_;
            $msg->send($url);
        });
    });

    if ($ENV{MOJOBOT_GOOGLE_IMAGES_HEAR}) {
        $robot->hear(qr/^(?:image|img) me (.*)/i => sub {
            my ($msg, $query) = @_;
            image_me($robot, $msg, $query, 0, 0, sub {
                my ($url) = @_;
                $msg->send($url);
            });
        });

        $robot->hear(qr/^animate me (.*)/i => sub {
            my ($msg, $query) = @_;
            image_me($robot, $msg, $query, 1, 0, sub {
                my ($url) = @_;
                $msg->send($url);
            });
        });
    }

    $robot->respond(qr/(?:mo?u)?sta(?:s|c)h(?:e|ify)?(?: me)? (.+)/i => sub {
        my ($msg, $imagery) = @_;
        my $mustacheBaseUrl = $ENV{MOJOBOT_MUSTACHIFY_URL};
        $mustacheBaseUrl =~ s{\/$}{};
        $mustacheBaseUrl ||= "http://mustachify.me";
        my $mustachify = "$mustacheBaseUrl/rand?src=";

        if ($imagery =~ m{^https?://}i) {
            my $encodedUrl = url_escape($imagery);
            $msg->send("$mustachify$encodedUrl");
        } else {
            image_me($robot, $msg, $imagery, 0, 1, sub {
                my ($url) = @_;
                my $encodedUrl = url_escape($url);
                $msg->send("$mustachify$encodedUrl");
            });
        }
    });

};

sub image_me {
    my ($robot, $msg, $query, $animated, $faces, $cb) = @_;
    $DB::single = 1;
    $cb = $animated if ref $animated eq 'CODE';
    $cb = $faces if ref $faces eq 'CODE';
    my $googleCseId = $ENV{MOJOBOT_GOOGLE_CSE_ID};
    if ($googleCseId) {
        # Using Google Custom Search API
        my $googleApiKey = $ENV{MOJOBOT_GOOGLE_CSE_ID};
        if (!$googleApiKey) {
            $robot->log->error('Missing environment variable MOJOBOT_GOOGLE_CSE_KEY');
            $msg->send('Missing server environment variable MOJOBOT_GOOGLE_CSE_KEY.');
            return;
        }

        my $q = {
            q => $query,
            searchType => 'image',
            safe => $ENV{MOJOBOT_GOOGLE_SAFE_SEARCH} || 'high',
            fields => 'items(link)',
            cx => $googleCseId,
            key => $googleApiKey,
        };

        if ($animated) {
            $q->{fileType} = 'gif';
            $q->{hq} = 'animated';
            $q->{tbs} = 'itp:animated';
        }

        if ($faces) {
            $q->{imgType} = 'face';
        }

        my $url = 'https://www.googleapis.com/customsearch/v1';
        $robot->ua->get(Mojo::URL->new($url)->query($q) => sub {
            my (undef, $tx) = @_;
            my $res = $tx->res;
            if (!$tx->success) {
                if ($res->code == 403) {
                    $msg->send('Daily image quota exceeded, using alternate source.');
                    deprecated_image($robot, $msg, $query, $animated, $faces, $cb);
                } else {
                    $msg->send('Encountered an error :( ' . $res->message);
                }
                return;
            }
            if ($res->code != 200) {
                $msg->send('Bad HTTP response :( ' . $res->code);
                return
            }
            my $response = $res->json;
            if ($response and $response->{responseData}{items} and @{$response->{responseData}{items}}) {
                my $image = $response->{responseData}{items}[rand @{$response->{responseData}{items}}];
                $cb->(ensure_result($image->{link}, $animated));
            } else {
                $msg->send("Oops. I had trouble searching '$query'. Try later.");
            }
        });
    } else {
        deprecated_image($robot, $msg, $query, $animated, $faces, $cb);
    }
}

sub deprecated_image {
    # Using deprecated Google image search API
    my ($robot, $msg, $query, $animated, $faces, $cb) = @_;
    my $q = {
        v => '1.0',
        rsz => '8',
        q => $query,
        safe => $ENV{MOJOBOT_GOOGLE_SAFE_SEARCH} || 'active',
    };
    if ($animated) {
        $q->{as_filetype} = 'gif';
        $q->{q} .= ' animated';
    }
    if ($faces) {
        $q->{as_filetype} = 'jpg';
        $q->{imgtype} = 'face';
    }

    $robot->ua->get(Mojo::URL->new('https://ajax.googleapis.com/ajax/services/search/images')->query($q) => sub {
        my (undef, $tx) = @_;
        my $err = $tx->error;
        if ($err) {
            $msg->send('Encountered an error :( ' . $err->message);
        }
        my $res = $tx->res;
        if ($res->code != 200) {
            $msg->send('Bad HTTP response :( ' . $res->code);
        }
        my $images = $res->json;
        if ($images and $images->{responseData}{results} and @{$images->{responseData}{results}}) {
            my $image = $images->{responseData}{results}[rand @{$images->{responseData}{results}}];
            $cb->(ensure_result($image->{unescapedUrl}, $animated));
        } else {
            $msg->send("Sorry, I found no results for '$query'.");
        }
    });
}

# Forces giphy result to use animated version
sub ensure_result {
    my ($url, $animated) = @_;
    if ($animated) {
        $url =~ s{/(giphy\.com/.*)/.+_s.gif$}{$1/giphy.gif};
        return ensure_image_extension($url);
    } else {
        return ensure_image_extension($url);
    }
}

# Forces the URL look like an image URL by adding `#.png`
sub ensure_image_extension {
    my ($url) = @_;
    if ($url =~ m{(png|jpe?g|gif)$}i) {
        return $url;
    } else {
        return "$url.png";
    }
}
