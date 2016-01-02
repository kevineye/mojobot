FROM perl:5.20
MAINTAINER kevineye@gmail.com

# add docker so mojobot can access other containers
RUN apt-get update -q \
 && apt-get install -y -q docker

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
