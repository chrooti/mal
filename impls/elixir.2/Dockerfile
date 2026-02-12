FROM ubuntu:24.04
MAINTAINER Alessandro Cerruti <whisper@chrooti.org>
LABEL org.opencontainers.image.source=https://github.com/kanaka/mal
LABEL org.opencontainers.image.description="mal test container: Elixir.2"
##########################################################
# General requirements for testing or common across many
# implementations
##########################################################

RUN apt-get -y update

# Required for running tests
RUN apt-get -y install make python3
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Some typical implementation and test requirements
RUN apt-get -y install curl libreadline-dev libedit-dev

RUN mkdir -p /mal
WORKDIR /mal

##########################################################
# Specific implementation requirements
##########################################################

# Elixir (14)
RUN apt-get install -y erlang-dev elixir
ENV HOME /mal