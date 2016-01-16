# mojobot
A port of [HUBOT](https://hubot.github.com/) and some [plugins](https://github.com/github/hubot-scripts/tree/master/src/scripts) to perl and [mojolicious](http://mojolicio.us/).

# Run

    # run daemon connecting to slack
    docker run -d --name mojobot \
        --restart always \
        -e MOJOBOT_SLACK_TOKEN=... \
        -e MOJOBOT_NAME=mojobot \
        -e MOJOBOT_SLACK_CHANNEL=#general \
        toolbox.acsu.buffalo.edu:5000/mojobot


    # run development mode, console IO
    docker run --rm -it -v $PWD:/app toolbox.acsu.buffalo.edu:5000/mojobot
