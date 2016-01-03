FROM perl:5.20
MAINTAINER kevineye@gmail.com

# add docker so mojobot can access other containers
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D \
 && echo 'deb http://apt.dockerproject.org/repo debian-jessie main' > /etc/apt/sources.list.d/docker.list \
 && apt-get update -q \
 && apt-get install -y -q docker-engine

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
