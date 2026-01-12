#!/usr/bin/python3

import phonetisaurus

words = {}

for line in open("db/en.dic"):
    items = line.split()
    if items[0] not in words:
         words[items[0]] = []
    words[items[0]].append(" ".join(items[1:]))

for line in open("db/extra.dic"):
    items = line.split()
    if items[0] not in words:
         words[items[0]] = []
    words[items[0]].append(" ".join(items[1:]))

new_words = set()
for line in open("db/extra.txt"):
    for w in line.split():
        if w not in words:
             new_words.add(w)

for w, phones in phonetisaurus.predict(new_words, "db/en-g2p/en.fst"):
    words[w] = []
    words[w].append(" ".join(phones))

for w, phones in words.items():
    for p in phones:
        print (w, p)


