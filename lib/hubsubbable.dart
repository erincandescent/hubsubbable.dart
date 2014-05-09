library hubsubbable;
import 'dart:async';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_route/shelf_route.dart';

var _l = new Logger("HubSubbable");

class _Subscription {
  StreamController<String> stream = new StreamController<String>();
  SubscriptionEndpoint endpoint;
  Uri uri, hubUri, callbackUri;
  Timer refreshTimer;
  
  sendSubscribe() {
    refreshTimer = new Timer(new Duration(minutes: 1), sendSubscribe);
    
    _l.info("Subscribing to ${uri} on ${hubUri}");
    
    var cli = new http.Client();
    var path = new List<String>.from(endpoint._selfUrl.pathSegments);
    path.add(uri.toString());
    
    callbackUri = endpoint._selfUrl.resolveUri(
        new Uri(pathSegments: path));
    
    var params = {
      'hub.callback': callbackUri.toString(),
      'hub.mode': 'subscribe',
      'hub.topic': uri.toString(),
      'hub.lease_seconds' : '86400',
      'hub.verify': 'sync'
    };
    
    _postData(cli, hubUri, params).then((http.Response resp) {
      if(resp.statusCode < 200 || resp.statusCode >= 300) {
        dropThis("Rejected: ${resp.statusCode} ${resp.body}");
      } else {
        _l.info("${uri} accepted");
      }
    });
  }
  
  dropThis(reason) {
    _l.info("Subscription ${uri} dropped: ${reason}");
        
    endpoint._subscriptions.remove(uri);
    refreshTimer.cancel();
        
    stream.addError(new Exception(reason));
    stream.close();
  }
  
  _Subscription(this.endpoint, this.uri, this.hubUri) {
    sendSubscribe();
  }
  
  onMessage(Request req) {
    if(req.method == "GET" || req.mimeType == "application/x-www-form-urlencoded") {
      // Subscription update
      
      return new Future.sync(() {
        if(req.method != "GET") {
          return req.readAsString().then((b) => Uri.splitQueryString(b)); 
        } else {
          return req.url.queryParameters;
        }
      }).then((params) { 
        if(params["hub.mode"] == "subscribe") {
          int leaseLength = int.parse(params["hub.lease_seconds"]);
            
          _l.info("Subscription accepted; expires in ${leaseLength} seconds");
            
          refreshTimer.cancel();
          refreshTimer = new Timer(new Duration(seconds: leaseLength ~/ 2), 
              sendSubscribe);
            
          return new Response.ok(params["hub.challenge"]);
        } else if(params["hub.mode"] == "denied") {
          dropThis("subscription denied!");
            
          return new Response.ok("");
        } else {
          _l.warning("Unexpected request: ${params}");
          return new Response.internalServerError();
        }
      });
    } else if(req.method == "POST") {
      return req.readAsString().then((body) {
        stream.add(body);
        
        _l.info("Notification from ${uri}");
          
        return new Response.ok("");
      });
    }
  }
}

Future<http.Response> _postData(http.Client cli, Uri uri, Map params) {
  String body = params.keys.map(
      (k) => Uri.encodeQueryComponent(k) + 
      "=" + Uri.encodeQueryComponent(params[k])).join("&");
  
  
  print("Sending request ${body}");
  return cli.post(uri, 
      headers: {"Content-Type" : "application/x-www-form-urlencoded"}, 
         body: body);
}

/** A PubSubHubub subscription endpoint.
 * 
 * 
 */
class SubscriptionEndpoint {
  final Uri    host;
  final String path;
  final Uri    _selfUrl;
  Map<Uri, _Subscription> _subscriptions = {};
  
  SubscriptionEndpoint(host, path)
      : host=host, path=path
      , _selfUrl = host.resolve(path);
  
  Stream<String> subscribe(Uri uri, Uri hub) {
    if(!_subscriptions.containsKey(uri)) {
      _subscriptions[uri] = new _Subscription(this, uri, hub);
    }
    
    return _subscriptions[uri].stream.stream.asBroadcastStream();
  }
  
  dynamic _dispatchRequest(Request req) {
    var path = req.url.pathSegments;
    if(path.length != 1) {
      return new Response.notFound("Bad path");
    }
    
    Uri topic = Uri.parse(path[0]);
    if(topic != null && _subscriptions.containsKey(topic)) {
      return _subscriptions[topic].onMessage(req);
    } else {
      _l.warning("Bad topic ${topic} ${req.requestedUri}");
      return new Response.notFound("Bad topic");
    }
  }

  Handler call(Handler h) {
    Router r = new Router();
    r.addRoute(_dispatchRequest, path: path);
    r.addRoute(h);
    
    return r.handler;
  }
}
