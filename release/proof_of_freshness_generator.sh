#!/bin/bash

## https://github.com/QubesOS/qubes-secpack/blob/master/utils/proof_of_freshness.py

set -e

export PS4="\n$ "
set -x

date -R -u

rsstail -1 -n5 -u https://www.spiegel.de/international/index.rss

rsstail -1 -n5 -u https://rss.nytimes.com/services/xml/rss/nyt/World.xml

rsstail -1 -n5 -u https://feeds.bbci.co.uk/news/world/rss.xml

#rsstail -1 -n5 -u http://feeds.reuters.com/reuters/worldnews

## broken --cert-status
curl --silent --fail --proto =https --tlsv1.3 https://blockchain.info/q/getblockcount

date -u "+%s"
