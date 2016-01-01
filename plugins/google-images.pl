# Description:
#   A way to interact with the Google Images API.
#
# Configuration
#   MOJOBOT_GOOGLE_CSE_KEY - Your Google developer API key
#   MOJOBOT_GOOGLE_CSE_ID - The ID of your Custom Search Engine
#   MOJOBOT_MUSTACHIFY_URL - Optional. Allow you to use your own mustachify instance.
#   MOJOBOT_GOOGLE_IMAGES_HEAR - Optional. If set, bot will respond to any line that begins with "image me" or "animate me" without needing to address the bot directly
#   MOJOBOT_GOOGLE_SAFE_SEARCH - Optional. Search safety level.
#   MOJOBOT_GOOGLE_IMAGES_FALLBACK - The URL to use when API fails. `{q}` will be replaced with the query string.
#
# Commands:
#   mojobot image me <query> - The Original. Queries Google Images for <query> and returns a random top result.
#   mojobot animate me <query> - The same thing as `image me`, except adds a few parameters to try to return an animated GIF instead.
#   mojobot mustache me <url|query> - Adds a mustache to the specified URL or query result.
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
        unless ($mustacheBaseUrl) {
            $msg->send("Sorry, the Mustachify server is not configured.");
            $msg->send("http://i.imgur.com/BXbGJ1N.png");
            return
        }
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
                    $msg->send('Encountered an error :( ' . $res->message . "\n" . $res->body);
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
        $msg->send("Google Image Search API is no longer available. " .
            "Please [setup up Custom Search Engine API](https://github.com/hubot-scripts/hubot-google-images#cse-setup-details).");
        deprecated_image($robot, $msg, $query, $animated, $faces, $cb);
    }
}

sub deprecated_image {
    my ($robot, $msg, $query, $animated, $faces, $cb) = @_;
    # Show a fallback image
    my $imgUrl = $ENV{MOJOBOT_GOOGLE_IMAGES_FALLBACK} ||
        'http://i.imgur.com/CzFTOkI.png';
    my $encoded_query = url_escape($query);
    $imgUrl =~ s{\{q\}}{$encoded_query}g;
    $cb->(ensure_result($imgUrl, $animated));
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
