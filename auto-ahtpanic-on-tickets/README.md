# auto-ahtpanic-on-tickets

A tool that:

* Gathers tickets from Zendesk (using a certain query)
* Processes each ticket:
  * Is ticket eligible?
  * Queue actions that need to be done on this ticket
  * Execute actions (like, postCommentAndFile, postComment, etc.)

Usage:

```
cd [this folder];
./run-ticket-watcher
```

Requirements:

* aht
* ahtpanic.sh
* php

