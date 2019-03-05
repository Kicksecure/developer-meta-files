#!/bin/bash


export PS4="\n$ "
set -x
set -e

date -R -u

rsstail -1 -n5 -u https://www.spiegel.de/international/index.rss

rsstail -1 -n5 -u https://rss.nytimes.com/services/xml/rss/nyt/World.xml

rsstail -1 -n5 -u https://feeds.bbci.co.uk/news/world/rss.xml

rsstail -1 -n5 -u http://feeds.reuters.com/reuters/worldnews

curl --silent --fail --proto =https --tlsv1.2 https://blockchain.info/blocks/?format=json | python3 -c "import sys, json; print(json.load(sys.stdin)['blocks'][10]['hash'])"
