A PubSubHubub receiver for Dart and Shelf.

Integrates as a Shelf middleware. Give it a path prefix, then subscribe to
PubSubHubub endpoints as you desire. 

Subscriptions are handled as streams. No attempt is made to process the 
submitted data for widest applicability (e.g. to support JSON payloads in 
addition to the traditional RSS and Atom).