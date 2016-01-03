FROM perl:5.20
MAINTAINER kevineye@gmail.com

# copy app and libs into place
COPY . /app
WORKDIR /app

# install dependencies
RUN cpanm -n --installdeps /app

# setup variables
ENV MOJOBOT_SLACK_TOKEN ''
ENV MOJOBOT_SLACK_CHANNEL '#general'
ENV MOJOBOT_NAME 'mojobot'

# run mojobot by default
CMD [ "/usr/local/bin/perl", "/app/mojobot.pl" ]
