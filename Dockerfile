
FROM ubuntu:bionic

MAINTAINER Devon P. Hubner

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get -y install wget supervisor rsyslog postfix sasl2-bin opendkim opendkim-tools ca-certificates libnss3-tools
RUN wget -O /usr/local/bin/mkcert "https://github.com/FiloSottile/mkcert/releases/download/v1.4.1/mkcert-v1.4.1-linux-amd64" ; chmod 0755 /usr/local/bin/mkcert

ADD assets/install.sh /opt/install.sh

CMD /opt/install.sh && /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
