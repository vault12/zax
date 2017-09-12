(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

function EventEmitter() {
  this._events = this._events || {};
  this._maxListeners = this._maxListeners || undefined;
}
module.exports = EventEmitter;

// Backwards-compat with node 0.10.x
EventEmitter.EventEmitter = EventEmitter;

EventEmitter.prototype._events = undefined;
EventEmitter.prototype._maxListeners = undefined;

// By default EventEmitters will print a warning if more than 10 listeners are
// added to it. This is a useful default which helps finding memory leaks.
EventEmitter.defaultMaxListeners = 10;

// Obviously not all Emitters should be limited to 10. This function allows
// that to be increased. Set to zero for unlimited.
EventEmitter.prototype.setMaxListeners = function(n) {
  if (!isNumber(n) || n < 0 || isNaN(n))
    throw TypeError('n must be a positive number');
  this._maxListeners = n;
  return this;
};

EventEmitter.prototype.emit = function(type) {
  var er, handler, len, args, i, listeners;

  if (!this._events)
    this._events = {};

  // If there is no 'error' event listener then throw.
  if (type === 'error') {
    if (!this._events.error ||
        (isObject(this._events.error) && !this._events.error.length)) {
      er = arguments[1];
      if (er instanceof Error) {
        throw er; // Unhandled 'error' event
      } else {
        // At least give some kind of context to the user
        var err = new Error('Uncaught, unspecified "error" event. (' + er + ')');
        err.context = er;
        throw err;
      }
    }
  }

  handler = this._events[type];

  if (isUndefined(handler))
    return false;

  if (isFunction(handler)) {
    switch (arguments.length) {
      // fast cases
      case 1:
        handler.call(this);
        break;
      case 2:
        handler.call(this, arguments[1]);
        break;
      case 3:
        handler.call(this, arguments[1], arguments[2]);
        break;
      // slower
      default:
        args = Array.prototype.slice.call(arguments, 1);
        handler.apply(this, args);
    }
  } else if (isObject(handler)) {
    args = Array.prototype.slice.call(arguments, 1);
    listeners = handler.slice();
    len = listeners.length;
    for (i = 0; i < len; i++)
      listeners[i].apply(this, args);
  }

  return true;
};

EventEmitter.prototype.addListener = function(type, listener) {
  var m;

  if (!isFunction(listener))
    throw TypeError('listener must be a function');

  if (!this._events)
    this._events = {};

  // To avoid recursion in the case that type === "newListener"! Before
  // adding it to the listeners, first emit "newListener".
  if (this._events.newListener)
    this.emit('newListener', type,
              isFunction(listener.listener) ?
              listener.listener : listener);

  if (!this._events[type])
    // Optimize the case of one listener. Don't need the extra array object.
    this._events[type] = listener;
  else if (isObject(this._events[type]))
    // If we've already got an array, just append.
    this._events[type].push(listener);
  else
    // Adding the second element, need to change to array.
    this._events[type] = [this._events[type], listener];

  // Check for listener leak
  if (isObject(this._events[type]) && !this._events[type].warned) {
    if (!isUndefined(this._maxListeners)) {
      m = this._maxListeners;
    } else {
      m = EventEmitter.defaultMaxListeners;
    }

    if (m && m > 0 && this._events[type].length > m) {
      this._events[type].warned = true;
      console.error('(node) warning: possible EventEmitter memory ' +
                    'leak detected. %d listeners added. ' +
                    'Use emitter.setMaxListeners() to increase limit.',
                    this._events[type].length);
      if (typeof console.trace === 'function') {
        // not supported in IE 10
        console.trace();
      }
    }
  }

  return this;
};

EventEmitter.prototype.on = EventEmitter.prototype.addListener;

EventEmitter.prototype.once = function(type, listener) {
  if (!isFunction(listener))
    throw TypeError('listener must be a function');

  var fired = false;

  function g() {
    this.removeListener(type, g);

    if (!fired) {
      fired = true;
      listener.apply(this, arguments);
    }
  }

  g.listener = listener;
  this.on(type, g);

  return this;
};

// emits a 'removeListener' event iff the listener was removed
EventEmitter.prototype.removeListener = function(type, listener) {
  var list, position, length, i;

  if (!isFunction(listener))
    throw TypeError('listener must be a function');

  if (!this._events || !this._events[type])
    return this;

  list = this._events[type];
  length = list.length;
  position = -1;

  if (list === listener ||
      (isFunction(list.listener) && list.listener === listener)) {
    delete this._events[type];
    if (this._events.removeListener)
      this.emit('removeListener', type, listener);

  } else if (isObject(list)) {
    for (i = length; i-- > 0;) {
      if (list[i] === listener ||
          (list[i].listener && list[i].listener === listener)) {
        position = i;
        break;
      }
    }

    if (position < 0)
      return this;

    if (list.length === 1) {
      list.length = 0;
      delete this._events[type];
    } else {
      list.splice(position, 1);
    }

    if (this._events.removeListener)
      this.emit('removeListener', type, listener);
  }

  return this;
};

EventEmitter.prototype.removeAllListeners = function(type) {
  var key, listeners;

  if (!this._events)
    return this;

  // not listening for removeListener, no need to emit
  if (!this._events.removeListener) {
    if (arguments.length === 0)
      this._events = {};
    else if (this._events[type])
      delete this._events[type];
    return this;
  }

  // emit removeListener for all listeners on all events
  if (arguments.length === 0) {
    for (key in this._events) {
      if (key === 'removeListener') continue;
      this.removeAllListeners(key);
    }
    this.removeAllListeners('removeListener');
    this._events = {};
    return this;
  }

  listeners = this._events[type];

  if (isFunction(listeners)) {
    this.removeListener(type, listeners);
  } else if (listeners) {
    // LIFO order
    while (listeners.length)
      this.removeListener(type, listeners[listeners.length - 1]);
  }
  delete this._events[type];

  return this;
};

EventEmitter.prototype.listeners = function(type) {
  var ret;
  if (!this._events || !this._events[type])
    ret = [];
  else if (isFunction(this._events[type]))
    ret = [this._events[type]];
  else
    ret = this._events[type].slice();
  return ret;
};

EventEmitter.prototype.listenerCount = function(type) {
  if (this._events) {
    var evlistener = this._events[type];

    if (isFunction(evlistener))
      return 1;
    else if (evlistener)
      return evlistener.length;
  }
  return 0;
};

EventEmitter.listenerCount = function(emitter, type) {
  return emitter.listenerCount(type);
};

function isFunction(arg) {
  return typeof arg === 'function';
}

function isNumber(arg) {
  return typeof arg === 'number';
}

function isObject(arg) {
  return typeof arg === 'object' && arg !== null;
}

function isUndefined(arg) {
  return arg === void 0;
}

},{}],2:[function(require,module,exports){
var Config;

Config = (function() {
  function Config() {}

  Config._NONCE_TAG = '__nc';

  Config._SKEY_TAG = 'storage_key';

  Config._DEF_ROOT = '.v1.stor.vlt12';

  Config.RELAY_TOKEN_LEN = 32;

  Config.RELAY_TOKEN_B64 = 44;

  Config.RELAY_TOKEN_TIMEOUT = 5 * 60 * 1000;

  Config.RELAY_SESSION_TIMEOUT = 15 * 60 * 1000;

  Config.RELAY_AJAX_TIMEOUT = 5 * 1000;

  Config.RELAY_RETRY_REQUEST_ATTEMPTS = 15;

  Config.RELAY_BLOCKING_TIME = 60 * 60 * 1000;

  return Config;

})();

module.exports = Config;


},{}],3:[function(require,module,exports){
var Config, CryptoStorage, Keys, Nacl, Utils;

Config = require('config');

Keys = require('keys');

Nacl = require('nacl');

Utils = require('utils');

CryptoStorage = (function() {
  function CryptoStorage() {}

  CryptoStorage.prototype._storageDriver = null;

  CryptoStorage.prototype.tag = function(strKey) {
    return strKey && strKey + this.root;
  };

  CryptoStorage["new"] = function(storageKey, r) {
    var cs;
    if (storageKey == null) {
      storageKey = null;
    }
    if (r == null) {
      r = null;
    }
    cs = new CryptoStorage;
    cs.storageKey = storageKey;
    cs.root = r ? "." + r + Config._DEF_ROOT : Config._DEF_ROOT;
    if (!cs.storageKey) {
      return cs._loadKey().then(function() {
        if (!cs.storageKey) {
          return cs.newKey().then(function() {
            return cs;
          });
        } else {
          return cs;
        }
      });
    } else {
      return Utils.resolve(cs);
    }
  };

  CryptoStorage.prototype._saveKey = function() {
    return this._set(Config._SKEY_TAG, this.storageKey.toString());
  };

  CryptoStorage.prototype._loadKey = function() {
    return this._get(Config._SKEY_TAG).then((function(_this) {
      return function(keyStr) {
        if (keyStr) {
          return _this.setKey(Keys.fromString(keyStr));
        }
      };
    })(this));
  };

  CryptoStorage.prototype.selfDestruct = function(overseerAuthorized) {
    Utils.ensure(overseerAuthorized);
    return this._localRemove(this.tag(Config._SKEY_TAG));
  };

  CryptoStorage.prototype.setKey = function(objStorageKey) {
    this.storageKey = objStorageKey;
    return this._saveKey();
  };

  CryptoStorage.prototype.newKey = function() {
    return Nacl.makeSecretKey().then((function(_this) {
      return function(key) {
        return _this.setKey(key);
      };
    })(this));
  };

  CryptoStorage.prototype.save = function(strTag, data) {
    Utils.ensure(strTag);
    data = JSON.stringify(data);
    return Nacl.use().encode_utf8(data).then((function(_this) {
      return function(data) {
        return Nacl.use().crypto_secretbox_random_nonce().then(function(nonce) {
          return Nacl.use().crypto_secretbox(data, nonce, _this.storageKey.key).then(function(aCText) {
            return _this._multiSet(strTag, aCText.toBase64(), Config._NONCE_TAG + "." + strTag, nonce.toBase64()).then(function() {
              return true;
            });
          });
        });
      };
    })(this));
  };

  CryptoStorage.prototype.get = function(strTag) {
    return this._get(strTag).then((function(_this) {
      return function(ct) {
        if (!ct) {
          return null;
        }
        return _this._get(Config._NONCE_TAG + "." + strTag).then(function(nonce) {
          if (!nonce) {
            return null;
          }
          return Nacl.use().crypto_secretbox_open(ct.fromBase64(), nonce.fromBase64(), _this.storageKey.key).then(function(aPText) {
            return Nacl.use().decode_utf8(aPText).then(function(data) {
              return JSON.parse(data);
            });
          });
        });
      };
    })(this));
  };

  CryptoStorage.prototype.remove = function(strTag) {
    return this._localRemove(this.tag(strTag)).then((function(_this) {
      return function() {
        return _this._localRemove(_this.tag(Config._NONCE_TAG + "." + strTag)).then(function() {
          return true;
        });
      };
    })(this));
  };

  CryptoStorage.prototype._get = function(strTag) {
    return this._localGet(this.tag(strTag));
  };

  CryptoStorage.prototype._set = function(strTag, strData) {
    Utils.ensure(strTag);
    return this._localSet(this.tag(strTag), strData).then(function() {
      return strData;
    });
  };

  CryptoStorage.prototype._multiSet = function(strTag1, strData1, strTag2, strData2) {
    Utils.ensure(strTag1, strTag2);
    if (this._storage().multiSet) {
      return this._localMultiSet([this.tag(strTag1), strData1, this.tag(strTag2), strData2]);
    } else {
      return this._set(strTag1, strData1).then((function(_this) {
        return function() {
          return _this._set(strTag2, strData2);
        };
      })(this));
    }
  };

  CryptoStorage.prototype._localGet = function(str) {
    return this._storage().get(str);
  };

  CryptoStorage.prototype._localSet = function(str, data) {
    return this._storage().set(str, data);
  };

  CryptoStorage.prototype._localMultiSet = function(pairs) {
    return this._storage().multiSet(pairs);
  };

  CryptoStorage.prototype._localRemove = function(str) {
    return this._storage().remove(str);
  };

  CryptoStorage.prototype._storage = function() {
    return CryptoStorage._storageDriver;
  };

  CryptoStorage.startStorageSystem = function(driver) {
    Utils.ensure(driver);
    return this._storageDriver = driver;
  };

  return CryptoStorage;

})();

module.exports = CryptoStorage;


},{"config":2,"keys":8,"nacl":12,"utils":16}],4:[function(require,module,exports){
var JsNaclDriver, Utils;

Utils = require('utils');

JsNaclDriver = (function() {
  JsNaclDriver.prototype._instance = null;

  JsNaclDriver.prototype._unloadTimer = null;

  function JsNaclDriver(js_nacl, HEAP_SIZE) {
    if (js_nacl == null) {
      js_nacl = null;
    }
    this.HEAP_SIZE = HEAP_SIZE != null ? HEAP_SIZE : Math.pow(2, 26);
    this.js_nacl = js_nacl || (typeof nacl_factory !== "undefined" && nacl_factory !== null ? nacl_factory : void 0) || require('js-nacl');
    this.load();
  }

  JsNaclDriver.prototype.use = function() {
    if (!this._instance) {
      throw new Error('js-nacl is not loaded');
    }
    return this._instance;
  };

  JsNaclDriver.prototype.load = function() {
    return nacl_factory.instantiate((function(_this) {
      return function(new_nacl) {
        _this._instance = new_nacl;
        _this.crypto_secretbox_KEYBYTES = _this.use().crypto_secretbox_KEYBYTES;
        return require('nacl').API.forEach(function(f) {
          return _this[f] = function() {
            var e, inst;
            inst = _this.use();
            try {
              return Utils.resolve(inst[f].apply(inst, arguments));
            } catch (error) {
              e = error;
              return Utils.reject(e);
            }
          };
        });
      };
    })(this), {
      requested_total_memory: this.HEAP_SIZE
    });
  };

  JsNaclDriver.prototype.unload = function() {
    this._instance = null;
    return delete this._instance;
  };

  return JsNaclDriver;

})();

module.exports = JsNaclDriver;

if (window.__CRYPTO_DEBUG) {
  window.JsNaclDriver = JsNaclDriver;
}


},{"js-nacl":undefined,"nacl":12,"utils":16}],5:[function(require,module,exports){
var JsNaclWebWorkerDriver, Utils;

Utils = require('utils');

JsNaclWebWorkerDriver = (function() {
  function JsNaclWebWorkerDriver(worker_path, js_nacl_path, heap_size) {
    var api, hasCrypto, onmessage2, queues, random_reqs, worker;
    if (worker_path == null) {
      worker_path = './build/js_nacl_worker.js';
    }
    if (js_nacl_path == null) {
      js_nacl_path = '../node_modules/js-nacl/lib/nacl_factory.js';
    }
    if (heap_size == null) {
      heap_size = Math.pow(2, 26);
    }
    random_reqs = {
      random_bytes: 32,
      crypto_box_keypair: 32,
      crypto_box_random_nonce: 24,
      crypto_secretbox_random_nonce: 24
    };
    hasCrypto = false;
    api = [];
    queues = {};
    worker = new Worker(worker_path);
    this.crypto_secretbox_KEYBYTES = 32;
    require('nacl').API.forEach((function(_this) {
      return function(f) {
        var queue;
        queue = [];
        queues[f] = queue;
        api.push(f);
        return _this[f] = function() {
          var args, n, p, refs, rnd;
          p = Utils.promise(function(res, rej) {
            return queue.push({
              resolve: res,
              reject: rej
            });
          });
          args = Array.prototype.slice.call(arguments);
          refs = [];
          rnd = null;
          if (!hasCrypto) {
            n = random_reqs[f];
            if (n) {
              rnd = new Uint8Array(32);
              crypto.getRandomValues(rnd);
            }
          }
          worker.postMessage({
            cmd: f,
            args: args,
            rnd: rnd
          }, refs);
          return p;
        };
      };
    })(this));
    onmessage2 = function(e) {
      var queue;
      queue = queues[e.data.cmd];
      if (e.data.error) {
        return queue.shift().reject(new Error(e.data.message));
      } else {
        return queue.shift().resolve(e.data.res);
      }
    };
    worker.onmessage = function(e) {
      if (e.data.cmd !== 'init') {
        throw new Error();
      }
      hasCrypto = e.data.hasCrypto;
      console.log('js nacl web worker initialized; hasCrypto: ' + hasCrypto);
      return worker.onmessage = onmessage2;
    };
    worker.postMessage({
      cmd: 'init',
      naclPath: js_nacl_path,
      heapSize: heap_size,
      api: api
    });
  }

  return JsNaclWebWorkerDriver;

})();

module.exports = JsNaclWebWorkerDriver;

if (window.__CRYPTO_DEBUG) {
  window.JsNaclDriver = JsNaclWebWorkerDriver;
}


},{"nacl":12,"utils":16}],6:[function(require,module,exports){
var KeyRatchet, Nacl;

Nacl = require('nacl');

KeyRatchet = (function() {
  function KeyRatchet() {}

  KeyRatchet.prototype.lastKey = null;

  KeyRatchet.prototype.confirmedKey = null;

  KeyRatchet.prototype.nextKey = null;

  KeyRatchet.prototype._roles = ['lastKey', 'confirmedKey', 'nextKey'];

  KeyRatchet["new"] = function(id, keyRing, firstKey) {
    var keys, kr;
    this.id = id;
    this.keyRing = keyRing;
    if (firstKey == null) {
      firstKey = null;
    }
    Utils.ensure(this.id, this.keyRing);
    kr = new KeyRatchet;
    keys = this._roles.map((function(_this) {
      return function(s) {
        return kr.keyRing.getKey(kr.keyTag(s)).then(function(key) {
          return kr[s] = key;
        });
      };
    })(this));
    return Utils.all(keys).then((function(_this) {
      return function() {
        if (firstKey) {
          return kr.startRatchet(firstKey).then(function() {
            return kr;
          });
        } else {
          return kr;
        }
      };
    })(this));
  };

  KeyRatchet.prototype.keyTag = function(role) {
    return role + "_" + this.id;
  };

  KeyRatchet.prototype.storeKey = function(role) {
    return this.keyRing.saveKey(this.keyTag(role), this[role]);
  };

  KeyRatchet.prototype.startRatchet = function(firstKey) {
    var keys;
    keys = ['confirmedKey', 'lastKey'].map((function(_this) {
      return function(k) {
        if (!_this[k]) {
          _this[k] = firstKey;
          return _this.storeKey(k);
        }
      };
    })(this));
    return Utils.all(keys).then((function(_this) {
      return function() {
        if (!_this.nextKey) {
          return Nacl.makeKeyPair().then(function(nextKey) {
            _this.nextKey = nextKey;
            return _this.storeKey('nextKey');
          });
        }
      };
    })(this));
  };

  KeyRatchet.prototype.pushKey = function(newKey) {
    this.lastKey = this.confirmedKey;
    this.confirmedKey = this.nextKey;
    this.nextKey = newKey;
    return Utils.all(this._roles.map((function(_this) {
      return function(s) {
        return _this.storeKey(s);
      };
    })(this)));
  };

  KeyRatchet.prototype.confKey = function(newConfirmedKey) {
    if (this.confirmedKey && this.confirmedKey.equal(newConfirmedKey)) {
      return Utils.resolve(false);
    }
    this.lastKey = this.confirmedKey;
    this.confirmedKey = newConfirmedKey;
    return Utils.all(['lastKey', 'confirmedKey'].map((function(_this) {
      return function(s) {
        return _this.storeKey(s);
      };
    })(this))).then(function() {
      return true;
    });
  };

  KeyRatchet.prototype.curKey = function() {
    if (this.confirmedKey) {
      return this.confirmedKey;
    }
    return this.lastKey;
  };

  KeyRatchet.prototype.h2LastKey = function() {
    return Nacl.h2(this.lastKey.boxPk);
  };

  KeyRatchet.prototype.h2ConfirmedKey = function() {
    return Nacl.h2(this.confirmedKey.boxPk);
  };

  KeyRatchet.prototype.h2NextKey = function() {
    return Nacl.h2(this.nextKey.boxPk);
  };

  KeyRatchet.prototype.keyByHash = function(hash) {
    return Utils.serial(this._roles, (function(_this) {
      return function(role) {
        return Nacl.h2(_this[s].boxPk).then(function(h2) {
          if (h2 === hash) {
            return _this[s];
          }
        });
      };
    })(this));
  };

  KeyRatchet.prototype.isNextKeyHash = function(hash) {
    return this.h2NextKey().then(function(h2) {
      return h2.equal(hash);
    });
  };

  KeyRatchet.prototype.toStr = function() {
    return JSON.stringify(this).toBase64();
  };

  KeyRatchet.prototype.fromStr = function(str) {
    return Utils.extend(this, JSON.parse(str.fromBase64()));
  };

  KeyRatchet.prototype.selfDestruct = function(overseerAuthorized) {
    Utils.ensure(overseerAuthorized);
    return Utils.all(this._roles.map((function(_this) {
      return function(s) {
        return _this.keyRing.deleteKey(_this.keyTag(s));
      };
    })(this)));
  };

  return KeyRatchet;

})();

module.exports = KeyRatchet;

if (window.__CRYPTO_DEBUG) {
  window.KeyRatchet = KeyRatchet;
}


},{"nacl":12}],7:[function(require,module,exports){
var Config, CryptoStorage, EventEmitter, KeyRing, Keys, Nacl, Utils, ensure,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

Config = require('config');

CryptoStorage = require('crypto_storage');

Keys = require('keys');

Nacl = require('nacl');

Utils = require('utils');

EventEmitter = require('events').EventEmitter;

ensure = Utils.ensure;

KeyRing = (function(superClass) {
  extend(KeyRing, superClass);

  function KeyRing() {
    return KeyRing.__super__.constructor.apply(this, arguments);
  }

  KeyRing["new"] = function(id, strMasterKey) {
    var key, kr, next;
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    kr = new KeyRing;
    if (strMasterKey) {
      key = Keys.fromString(strMasterKey);
      next = CryptoStorage["new"](key, id).then((function(_this) {
        return function(storage) {
          return kr.storage = storage;
        };
      })(this));
    } else {
      next = CryptoStorage["new"](null, id).then((function(_this) {
        return function(storage) {
          return kr.storage = storage;
        };
      })(this));
    }
    return next.then((function(_this) {
      return function() {
        return kr._ensureKeys().then(function() {
          return kr;
        });
      };
    })(this));
  };

  KeyRing.UNIQ_TAG = "__::commKey::__";

  KeyRing.fromBackup = function(id, strBackup) {
    var data, fillGuests, strCommKey;
    ensure(strBackup);
    data = JSON.parse(strBackup);
    strCommKey = data[this.UNIQ_TAG];
    ensure(strCommKey);
    delete data[this.UNIQ_TAG];
    fillGuests = function(p, kr) {
      return p.then(function() {
        var key, name, pa;
        pa = (function() {
          var results;
          results = [];
          for (name in data) {
            key = data[name];
            results.push(kr.addGuest(name, data[name]));
          }
          return results;
        })();
        return Utils.all(pa);
      });
    };
    return KeyRing["new"](id).then(function(kr) {
      var p;
      p = kr.commFromSecKey(strCommKey.fromBase64());
      return [p, kr];
    }).then(function(args) {
      var kr, p;
      p = args[0], kr = args[1];
      return fillGuests(p, kr).then(function() {
        return kr;
      });
    });
  };

  KeyRing.prototype._ensureKeys = function() {
    return this._loadCommKey().then((function(_this) {
      return function() {
        return _this._loadGuestKeys();
      };
    })(this));
  };

  KeyRing.prototype._loadCommKey = function() {
    return this.getKey('comm_key').then((function(_this) {
      return function(commKey) {
        _this.commKey = commKey;
        if (_this.commKey) {
          return Nacl.h2(_this.commKey.boxPk).then(function(hpk) {
            _this.hpk = hpk;
            return _this.commKey;
          });
        } else {
          return Nacl.makeKeyPair().then(function(commKey) {
            _this.commKey = commKey;
            return Nacl.h2(_this.commKey.boxPk).then(function(hpk) {
              return _this.hpk = hpk;
            }).then(function() {
              _this.saveKey('comm_key', _this.commKey);
              return _this.commKey;
            });
          });
        }
      };
    })(this));
  };

  KeyRing.prototype.getNumberOfGuests = function() {
    return Object.keys(this.guestKeys || {}).length;
  };

  KeyRing.prototype._loadGuestKeys = function() {
    return this.storage.get('guest_registry').then((function(_this) {
      return function(guestKeys) {
        _this.guestKeys = guestKeys || {};
        return _this.guestKeyTimeouts = {};
      };
    })(this));
  };

  KeyRing.prototype.commFromSeed = function(seed) {
    return Nacl.encode_utf8(seed).then((function(_this) {
      return function(encoded) {
        return Nacl.fromSeed(encoded).then(function(commKey) {
          _this.commKey = commKey;
          return Nacl.h2(_this.commKey.boxPk).then(function(hpk) {
            return _this.hpk = hpk;
          }).then(function() {
            _this.storage.save('comm_key', _this.commKey.toString());
            return _this.commKey;
          });
        });
      };
    })(this));
  };

  KeyRing.prototype.commFromSecKey = function(rawSecKey) {
    return Nacl.fromSecretKey(rawSecKey).then((function(_this) {
      return function(commKey) {
        _this.commKey = commKey;
        return Nacl.h2(_this.commKey.boxPk).then(function(hpk) {
          return _this.hpk = hpk;
        }).then(function() {
          _this.storage.save('comm_key', _this.commKey.toString());
          return _this.commKey;
        });
      };
    })(this));
  };

  KeyRing.prototype.tagByHpk = function(hpk) {
    var k, ref, v;
    ref = this.guestKeys;
    for (k in ref) {
      if (!hasProp.call(ref, k)) continue;
      v = ref[k];
      if (hpk === v.hpk) {
        return k;
      }
    }
    return null;
  };

  KeyRing.prototype.getMasterKey = function() {
    return this.storage.storageKey.key2str('key');
  };

  KeyRing.prototype.getPubCommKey = function() {
    return this.commKey.strPubKey();
  };

  KeyRing.prototype.saveKey = function(tag, key) {
    return this.storage.save(tag, key.toString()).then(function() {
      return key;
    });
  };

  KeyRing.prototype.getKey = function(tag) {
    return this.storage.get(tag).then(function(k) {
      if (k) {
        return Keys.fromString(k);
      } else {
        return null;
      }
    });
  };

  KeyRing.prototype.deleteKey = function(tag) {
    return this.storage.remove(tag);
  };

  KeyRing.prototype.addGuest = function(strGuestTag, b64_pk) {
    ensure(strGuestTag, b64_pk);
    b64_pk = b64_pk.trimLines();
    return this._addGuestRecord(strGuestTag, b64_pk).then((function(_this) {
      return function(guest) {
        return _this._saveNewGuest(strGuestTag, guest).then(function() {
          return guest.hpk;
        });
      };
    })(this));
  };

  KeyRing.prototype._addGuestRecord = function(strGuestTag, b64_pk) {
    ensure(strGuestTag, b64_pk);
    return Nacl.h2(b64_pk.fromBase64()).then((function(_this) {
      return function(h2) {
        return _this.guestKeys[strGuestTag] = {
          pk: b64_pk,
          hpk: h2.toBase64(),
          temp: false
        };
      };
    })(this));
  };

  KeyRing.prototype._saveNewGuest = function(tag, pk) {
    ensure(tag, pk);
    return this.storage.save('guest_registry', this.guestKeys);
  };

  KeyRing.prototype.timeToGuestExpiration = function(strGuestTag) {
    var entry;
    ensure(strGuestTag);
    entry = this.guestKeyTimeouts[strGuestTag];
    if (!entry) {
      return 0;
    }
    return Math.max(Config.RELAY_SESSION_TIMEOUT - (Date.now() - entry.startTime), 0);
  };

  KeyRing.prototype.addTempGuest = function(strGuestTag, strPubKey) {
    ensure(strGuestTag, strPubKey);
    strPubKey = strPubKey.trimLines();
    return Nacl.h2(strPubKey.fromBase64()).then((function(_this) {
      return function(h2) {
        _this.guestKeys[strGuestTag] = {
          pk: strPubKey,
          hpk: h2.toBase64(),
          temp: true
        };
        if (_this.guestKeyTimeouts[strGuestTag]) {
          clearTimeout(_this.guestKeyTimeouts[strGuestTag].timeoutId);
        }
        return _this.guestKeyTimeouts[strGuestTag] = {
          timeoutId: Utils.delay(Config.RELAY_SESSION_TIMEOUT, function() {
            delete _this.guestKeys[strGuestTag];
            delete _this.guestKeyTimeouts[strGuestTag];
            return _this.emit('tmpguesttimeout', strGuestTag);
          }),
          startTime: Date.now()
        };
      };
    })(this));
  };

  KeyRing.prototype.removeGuest = function(strGuestTag) {
    ensure(strGuestTag);
    if (!this.guestKeys[strGuestTag]) {
      return Utils.resolve();
    }
    delete this.guestKeys[strGuestTag];
    return this.storage.save('guest_registry', this.guestKeys);
  };

  KeyRing.prototype.getGuestKey = function(strGuestTag) {
    ensure(strGuestTag);
    if (!this.guestKeys[strGuestTag]) {
      return null;
    }
    return new Keys({
      boxPk: this.getGuestRecord(strGuestTag).fromBase64()
    });
  };

  KeyRing.prototype.getGuestRecord = function(strGuestTag) {
    ensure(strGuestTag);
    if (!this.guestKeys[strGuestTag]) {
      return null;
    }
    return this.guestKeys[strGuestTag].pk;
  };

  KeyRing.prototype.backup = function() {
    var k, ref, res, v;
    res = {};
    if (this.getNumberOfGuests() > 0) {
      ref = this.guestKeys;
      for (k in ref) {
        v = ref[k];
        if (!v.temp) {
          res[k] = v.pk;
        }
      }
    }
    res[KeyRing.UNIQ_TAG] = this.commKey.strSecKey();
    return JSON.stringify(res);
  };

  KeyRing.prototype.selfDestruct = function(overseerAuthorized) {
    ensure(overseerAuthorized);
    return this.storage.remove('guest_registry').then((function(_this) {
      return function() {
        return _this.storage.remove('comm_key').then(function() {
          return _this.storage.selfDestruct(overseerAuthorized);
        });
      };
    })(this));
  };

  return KeyRing;

})(EventEmitter);

module.exports = KeyRing;

if (window.__CRYPTO_DEBUG) {
  window.KeyRing = KeyRing;
}


},{"config":2,"crypto_storage":3,"events":1,"keys":8,"nacl":12,"utils":16}],8:[function(require,module,exports){
var Keys, Utils,
  hasProp = {}.hasOwnProperty;

Utils = require('utils');

Keys = (function() {
  function Keys(hashKeys) {
    if (!hashKeys) {
      return;
    }
    Utils.extend(this, hashKeys);
  }

  Keys.prototype.toString = function() {
    return JSON.stringify(this.constructor.keys2str(this));
  };

  Keys.fromString = function(strKeys) {
    if (!strKeys) {
      return null;
    }
    return this.str2keys(JSON.parse(strKeys.trimLines()));
  };

  Keys.prototype.key2str = function(strName) {
    if (!(strName && (this[strName] != null))) {
      return null;
    }
    return this[strName].toBase64();
  };

  Keys.prototype.strPubKey = function() {
    return this.boxPk.toBase64();
  };

  Keys.prototype.strSecKey = function() {
    return this.boxSk.toBase64();
  };

  Keys.prototype.equal = function(k) {
    if (this.strPubKey() !== k.strPubKey()) {
      return false;
    }
    if ((this.boxSk != null) !== (k.boxSk != null)) {
      return false;
    }
    if (this.boxSk != null) {
      return this.strSecKey() === k.strSecKey();
    }
    return true;
  };

  Keys.keys2str = function(objKey) {
    var k, r, v;
    r = new Keys();
    for (k in objKey) {
      if (!hasProp.call(objKey, k)) continue;
      v = objKey[k];
      r[k] = v.toBase64();
    }
    return r;
  };

  Keys.str2keys = function(strObj) {
    var k, r, v;
    r = new Keys();
    for (k in strObj) {
      if (!hasProp.call(strObj, k)) continue;
      v = strObj[k];
      r[k] = v.fromBase64();
    }
    return r;
  };

  return Keys;

})();

module.exports = Keys;

if (window.__CRYPTO_DEBUG) {
  window.Keys = Keys;
}


},{"utils":16}],9:[function(require,module,exports){
var Config, EventEmitter, KeyRing, MailBox, Nacl, Utils,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

Config = require('config');

KeyRing = require('keyring');

Nacl = require('nacl');

Utils = require('utils');

EventEmitter = require('events').EventEmitter;

MailBox = (function(superClass) {
  extend(MailBox, superClass);

  function MailBox() {
    return MailBox.__super__.constructor.apply(this, arguments);
  }

  MailBox["new"] = function(identity, strMasterKey) {
    var mbx;
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    mbx = new MailBox();
    mbx.identity = identity;
    mbx.sessionKeys = {};
    mbx.sessionTimeout = {};
    return KeyRing["new"](mbx.identity, strMasterKey).then(function(keyRing) {
      mbx.keyRing = keyRing;
      return mbx;
    });
  };

  MailBox.fromSeed = function(seed, id, strMasterKey) {
    if (id == null) {
      id = seed;
    }
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    return this["new"](id, strMasterKey, false).then((function(_this) {
      return function(mbx) {
        return mbx.keyRing.commFromSeed(seed).then(function() {
          return mbx;
        });
      };
    })(this));
  };

  MailBox.fromSecKey = function(secKey, id, strMasterKey) {
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    return this["new"](id, strMasterKey, false).then((function(_this) {
      return function(mbx) {
        return mbx.keyRing.commFromSecKey(secKey).then(function() {
          return mbx;
        });
      };
    })(this));
  };

  MailBox.fromBackup = function(strBackup, id, strMasterKey) {
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    return this["new"](id, strMasterKey, false).then(function(mbx) {
      return KeyRing.fromBackup(id, strBackup).then(function(kr) {
        mbx.keyRing = kr;
        return mbx;
      });
    });
  };

  MailBox.prototype.hpk = function() {
    return this.keyRing.hpk.toBase64();
  };

  MailBox.prototype.getPubCommKey = function() {
    return this.keyRing.getPubCommKey();
  };

  MailBox.prototype.timeToSessionExpiration = function(sess_id) {
    var guExp, sesExp, session;
    session = this.sessionTimeout[sess_id];
    if (!session) {
      return 0;
    }
    sesExp = Math.max(Config.RELAY_SESSION_TIMEOUT - (Date.now() - session.startTime), 0);
    guExp = this.keyRing.timeToGuestExpiration(sess_id);
    return Math.min(sesExp, guExp);
  };

  MailBox.prototype.createSessionKey = function(sess_id, forceNew) {
    if (forceNew == null) {
      forceNew = false;
    }
    Utils.ensure(sess_id);
    if (!forceNew && this.sessionKeys[sess_id]) {
      return Utils.resolve(this.sessionKeys[sess_id]);
    }
    if (this.sessionTimeout[sess_id]) {
      clearTimeout(this.sessionTimeout[sess_id].timeoutId);
    }
    return Nacl.makeKeyPair().then((function(_this) {
      return function(key) {
        _this.sessionKeys[sess_id] = key;
        _this.sessionTimeout[sess_id] = {
          timeoutId: Utils.delay(Config.RELAY_SESSION_TIMEOUT, function() {
            return _this._clearSession(sess_id);
          }),
          startTime: Date.now()
        };
        return key;
      };
    })(this));
  };

  MailBox.prototype._clearSession = function(sess_id) {
    this.sessionKeys[sess_id] = null;
    delete this.sessionKeys[sess_id];
    this.sessionTimeout[sess_id] = null;
    delete this.sessionTimeout[sess_id];
    return this.emit('relaysessiontimeout', sess_id);
  };

  MailBox.prototype.isConnectedToRelay = function(relay) {
    var relayId;
    Utils.ensure(relay);
    relayId = relay.relayId();
    return Boolean(this.sessionKeys[relayId]) && Boolean(this._gPk(relayId));
  };

  MailBox.prototype.rawEncodeMessage = function(msg, pkTo, skFrom, nonceData) {
    if (nonceData == null) {
      nonceData = null;
    }
    Utils.ensure(msg, pkTo, skFrom);
    return MailBox._makeNonce(nonceData).then((function(_this) {
      return function(nonce) {
        return _this._parseData(msg).then(function(data) {
          return Nacl.use().crypto_box(data, nonce, pkTo, skFrom).then(function(ctext) {
            return {
              nonce: nonce.toBase64(),
              ctext: ctext.toBase64()
            };
          });
        });
      };
    })(this));
  };

  MailBox.prototype.rawDecodeMessage = function(nonce, ctext, pkFrom, skTo) {
    Utils.ensure(nonce, ctext, pkFrom, skTo);
    return Nacl.use().crypto_box_open(ctext, nonce, pkFrom, skTo).then(function(data) {
      return Nacl.use().decode_utf8(data).then(function(utf8) {
        return JSON.parse(utf8);
      });
    });
  };

  MailBox.prototype.encodeMessage = function(guest, msg, session, skTag) {
    var gpk, sk;
    if (session == null) {
      session = false;
    }
    if (skTag == null) {
      skTag = null;
    }
    Utils.ensure(guest, msg);
    if (!(gpk = this._gPk(guest))) {
      throw new Error("encodeMessage: don't know guest " + guest);
    }
    sk = this._getSecretKey(guest, session, skTag);
    return this.rawEncodeMessage(msg, gpk, sk);
  };

  MailBox.prototype.encodeMessageSymmetric = function(msg, sk) {
    Utils.ensure(msg, sk);
    return MailBox._makeNonce().then((function(_this) {
      return function(nonce) {
        return Nacl.use().encode_latin1(msg).then(function(data) {
          return Nacl.use().crypto_secretbox(data, nonce, sk).then(function(ctext) {
            return {
              nonce: nonce.toBase64(),
              ctext: ctext.toBase64()
            };
          });
        });
      };
    })(this));
  };

  MailBox.prototype.decodeMessage = function(guest, nonce, ctext, session, skTag) {
    var gpk, sk;
    if (session == null) {
      session = false;
    }
    if (skTag == null) {
      skTag = null;
    }
    Utils.ensure(guest, nonce, ctext);
    if (!(gpk = this._gPk(guest))) {
      throw new Error("decodeMessage: don't know guest " + guest);
    }
    sk = this._getSecretKey(guest, session, skTag);
    return this.rawDecodeMessage(nonce.fromBase64(), ctext.fromBase64(), gpk, sk);
  };

  MailBox.prototype.decodeMessageSymmetric = function(nonce, ctext, sk) {
    Utils.ensure(nonce, ctext, sk);
    return Nacl.use().crypto_secretbox_open(ctext.fromBase64(), nonce.fromBase64(), sk.fromBase64()).then((function(_this) {
      return function(data) {
        return Nacl.use().decode_latin1(data);
      };
    })(this));
  };

  MailBox.prototype.connectToRelay = function(relay) {
    Utils.ensure(relay);
    return relay.openConnection().then((function(_this) {
      return function() {
        return relay.connectMailbox(_this);
      };
    })(this));
  };

  MailBox.prototype.sendToVia = function(guest, relay, msg) {
    Utils.ensure(guest, relay, msg);
    return this.connectToRelay(relay).then((function(_this) {
      return function() {
        return _this.relaySend(guest, msg, relay);
      };
    })(this));
  };

  MailBox.prototype.getRelayMessages = function(relay) {
    Utils.ensure(relay);
    return this.connectToRelay(relay).then((function(_this) {
      return function() {
        return _this.relayMessages(relay);
      };
    })(this));
  };

  MailBox.prototype.relayCount = function(relay) {
    Utils.ensure(relay);
    return relay.count(this).then((function(_this) {
      return function(result) {
        return parseInt(result);
      };
    })(this));
  };

  MailBox.prototype.relay_msg_status = function(relay, storage_token) {
    Utils.ensure(relay);
    return relay.messageStatus(this, storage_token).then((function(_this) {
      return function(ttl) {
        return ttl;
      };
    })(this));
  };

  MailBox.prototype.relaySend = function(guest, msg, relay) {
    Utils.ensure(relay);
    return this.encodeMessage(guest, msg).then((function(_this) {
      return function(encMsg) {
        return Nacl.h2(_this._gPk(guest)).then(function(h2) {
          return relay.upload(_this, h2, encMsg);
        });
      };
    })(this));
  };

  MailBox.prototype.relayMessages = function(relay) {
    Utils.ensure(relay);
    return relay.download(this).then((function(_this) {
      return function(result) {
        return Utils.all(result.map(function(emsg) {
          var tag;
          if ((tag = _this.keyRing.tagByHpk(emsg.from))) {
            emsg['fromTag'] = tag;
            if (emsg['kind'] === 'file') {
              emsg = JSON.parse(emsg.data);
              return _this.decodeMessage(tag, emsg.nonce, emsg.ctext).then(function(msg) {
                msg.uploadID = emsg.uploadID;
                return msg;
              });
            } else {
              return _this.decodeMessage(tag, emsg.nonce, emsg.data).then(function(msg) {
                if (msg) {
                  emsg['msg'] = msg;
                  delete emsg.data;
                }
                return emsg;
              });
            }
          } else {
            return emsg;
          }
        }));
      };
    })(this));
  };

  MailBox.prototype.relayNonceList = function(download) {
    Utils.ensure(download);
    return download.map(function(i) {
      return i.nonce;
    });
  };

  MailBox.prototype.relayDelete = function(list, relay) {
    Utils.ensure(list, relay);
    return relay["delete"](this, list);
  };

  MailBox.prototype.clean = function(relay) {
    Utils.ensure(relay);
    return this.getRelayMessages(relay).then((function(_this) {
      return function(download) {
        return _this.relayDelete(_this.relayNonceList(download), relay);
      };
    })(this));
  };

  MailBox.prototype.selfDestruct = function(overseerAuthorized) {
    Utils.ensure(overseerAuthorized);
    return this.keyRing.selfDestruct(overseerAuthorized);
  };

  MailBox.prototype.getFileMetadata = function(relay, uploadID) {
    Utils.ensure(relay, uploadID);
    return this.relayMessages(relay).then((function(_this) {
      return function(msgs) {
        msgs = msgs.filter(function(msg) {
          return msg.uploadID === uploadID;
        });
        return msgs[0];
      };
    })(this));
  };

  MailBox.prototype.startFileUpload = function(guest, relay, fileMetadata) {
    Utils.ensure(relay, guest, fileMetadata);
    return Nacl.h2(this._gPk(guest)).then((function(_this) {
      return function(hpk) {
        return Nacl.makeSecretKey().then(function(sk) {
          fileMetadata.skey = sk.key.toBase64();
          return _this.encodeMessage(guest, fileMetadata).then(function(encodedMetadata) {
            return _this.connectToRelay(relay).then(function() {
              var fileSize;
              fileSize = fileMetadata.orig_size;
              return relay.startFileUpload(_this, hpk, fileSize, encodedMetadata).then(function(response) {
                response.skey = sk.key;
                return response;
              });
            });
          });
        });
      };
    })(this));
  };

  MailBox.prototype.uploadFileChunk = function(relay, uploadID, chunk, part, totalParts, skey) {
    Utils.ensure(relay, uploadID, chunk, totalParts, skey);
    return this.encodeMessageSymmetric(chunk, skey).then((function(_this) {
      return function(encodedChunk) {
        return _this.connectToRelay(relay).then(function() {
          return relay.uploadFileChunk(_this, uploadID, part, totalParts, encodedChunk);
        });
      };
    })(this));
  };

  MailBox.prototype.getFileStatus = function(relay, uploadID) {
    Utils.ensure(relay, uploadID);
    return this.connectToRelay(relay).then((function(_this) {
      return function() {
        return relay.fileStatus(_this, uploadID);
      };
    })(this));
  };

  MailBox.prototype.downloadFileChunk = function(relay, uploadID, part, skey) {
    Utils.ensure(relay, uploadID, skey);
    return this.connectToRelay(relay).then((function(_this) {
      return function() {
        return relay.downloadFileChunk(_this, uploadID, part).then(function(encodedChunk) {
          return _this.decodeMessageSymmetric(encodedChunk.nonce, encodedChunk.ctext, skey);
        });
      };
    })(this));
  };

  MailBox.prototype.deleteFile = function(relay, uploadID) {
    Utils.ensure(relay, uploadID);
    return this.connectToRelay(relay).then((function(_this) {
      return function() {
        return relay.deleteFile(_this, uploadID);
      };
    })(this));
  };

  MailBox.prototype._gKey = function(strId) {
    Utils.ensure(strId);
    return this.keyRing.getGuestKey(strId);
  };

  MailBox.prototype._gPk = function(strId) {
    var ref;
    Utils.ensure(strId);
    return (ref = this._gKey(strId)) != null ? ref.boxPk : void 0;
  };

  MailBox.prototype._gHpk = function(strId) {
    Utils.ensure(strId);
    return Nacl.h2(this._gPk(strId));
  };

  MailBox.prototype._getSecretKey = function(guest, session, skTag) {
    if (!skTag) {
      if (session) {
        return this.sessionKeys[guest].boxSk;
      } else {
        return this.keyRing.commKey.boxSk;
      }
    } else {
      return this._gPk(skTag);
    }
  };

  MailBox.prototype._parseData = function(data) {
    if (Utils.type(data) === 'Uint8Array') {
      return Utils.resolve(data);
    }
    return Nacl.use().encode_utf8(JSON.stringify(data));
  };

  MailBox._makeNonce = function(data, time) {
    if (data == null) {
      data = null;
    }
    if (time == null) {
      time = Date.now();
    }
    return Nacl.use().crypto_box_random_nonce().then(function(nonce) {
      var aData, aTime, headerLen, i, j, k, l, ref, ref1, ref2;
      if (!((nonce != null) && nonce.length === 24)) {
        throw new Error('RNG failed, try again?');
      }
      headerLen = 8;
      aTime = Utils.itoa(parseInt(time / 1000));
      if (data) {
        aData = Utils.itoa(data);
        headerLen += 4;
      }
      for (i = j = 0, ref = headerLen; 0 <= ref ? j < ref : j > ref; i = 0 <= ref ? ++j : --j) {
        nonce[i] = 0;
      }
      for (i = k = 0, ref1 = aTime.length - 1; 0 <= ref1 ? k <= ref1 : k >= ref1; i = 0 <= ref1 ? ++k : --k) {
        nonce[8 - aTime.length + i] = aTime[i];
      }
      if (data) {
        for (i = l = 0, ref2 = aData.length - 1; 0 <= ref2 ? l <= ref2 : l >= ref2; i = 0 <= ref2 ? ++l : --l) {
          nonce[12 - aData.length + i] = aData[i];
        }
      }
      return nonce;
    });
  };

  MailBox._nonceData = function(nonce) {
    return Utils.atoi(nonce.subarray(8, 12));
  };

  return MailBox;

})(EventEmitter);

module.exports = MailBox;

if (window.__CRYPTO_DEBUG) {
  window.MailBox = MailBox;
}


},{"config":2,"events":1,"keyring":7,"nacl":12,"utils":16}],10:[function(require,module,exports){
module.exports = {
  Utils: require('utils'),
  Mixins: require('mixins'),
  Nacl: require('nacl'),
  Keys: require('keys'),
  SimpleStorageDriver: require('test_driver'),
  CryptoStorage: require('crypto_storage'),
  KeyRing: require('keyring'),
  MailBox: require('mailbox'),
  Relay: require('relay'),
  RachetBox: require('rachetbox'),
  Config: require('config'),
  JsNaclDriver: require('js_nacl_driver'),
  JsNaclWebWorkerDriver: require('js_nacl_worker_driver'),
  setNaclImpl: function(naclImpl) {
    return this.Nacl.setNaclImpl(naclImpl);
  },
  setPromiseImpl: function(promiseImpl) {
    return this.Utils.setPromiseImpl(promiseImpl);
  },
  startStorageSystem: function(storeImpl) {
    return this.CryptoStorage.startStorageSystem(storeImpl);
  },
  setAjaxImpl: function(ajaxImpl) {
    return this.Utils.setAjaxImpl(ajaxImpl);
  }
};

if (window) {
  window.glow = module.exports;
}


},{"config":2,"crypto_storage":3,"js_nacl_driver":4,"js_nacl_worker_driver":5,"keyring":7,"keys":8,"mailbox":9,"mixins":11,"nacl":12,"rachetbox":13,"relay":14,"test_driver":15,"utils":16}],11:[function(require,module,exports){
var C, Utils, j, len, ref;

Utils = require('utils');

Utils.include(String, {
  toCodeArray: function() {
    var j, len, ref, results, s;
    ref = this;
    results = [];
    for (j = 0, len = ref.length; j < len; j++) {
      s = ref[j];
      results.push(s.charCodeAt());
    }
    return results;
  },
  toUTF8: function() {
    return unescape(encodeURIComponent(this));
  },
  fromUTF8: function() {
    return decodeURIComponent(escape(this));
  },
  toUint8Array: function() {
    return new Uint8Array(this.toUTF8().toCodeArray());
  },
  toUint8ArrayRaw: function() {
    return new Uint8Array(this.toCodeArray());
  },
  fromBase64: function() {
    return new Uint8Array((atob(this)).toCodeArray());
  },
  trimLines: function() {
    return this.replace('\r\n', '').replace('\n', '').replace('\r', '');
  }
});

ref = [Array, Uint8Array, Uint16Array];
for (j = 0, len = ref.length; j < len; j++) {
  C = ref[j];
  Utils.include(C, {
    fromCharCodes: function() {
      var c;
      return ((function() {
        var k, len1, ref1, results;
        ref1 = this;
        results = [];
        for (k = 0, len1 = ref1.length; k < len1; k++) {
          c = ref1[k];
          results.push(String.fromCharCode(c));
        }
        return results;
      }).call(this)).join('');
    },
    toBase64: function() {
      return btoa(this.fromCharCodes());
    },
    xorWith: function(a) {
      var c, i;
      if (this.length !== a.length) {
        return null;
      }
      return new Uint8Array((function() {
        var k, len1, ref1, results;
        ref1 = this;
        results = [];
        for (i = k = 0, len1 = ref1.length; k < len1; i = ++k) {
          c = ref1[i];
          results.push(c ^ a[i]);
        }
        return results;
      }).call(this));
    },
    equal: function(a2) {
      var i, k, len1, ref1, v;
      if (this.length !== a2.length) {
        return false;
      }
      ref1 = this;
      for (i = k = 0, len1 = ref1.length; k < len1; i = ++k) {
        v = ref1[i];
        if (v !== a2[i]) {
          return false;
        }
      }
      return true;
    },
    sample: function() {
      if (!(this.length > 0)) {
        return null;
      }
      return this[Math.floor(Math.random() * this.length)];
    }
  });
}

Utils.include(Uint8Array, {
  concat: function(anotherArray) {
    var tmp;
    tmp = new Uint8Array(this.byteLength + anotherArray.byteLength);
    tmp.set(new Uint8Array(this), 0);
    tmp.set(anotherArray, this.byteLength);
    return tmp;
  },
  fillWith: function(val) {
    var i, k, len1, ref1, v;
    ref1 = this;
    for (i = k = 0, len1 = ref1.length; k < len1; i = ++k) {
      v = ref1[i];
      this[i] = val;
    }
    return this;
  }
});

module.exports = {};


},{"utils":16}],12:[function(require,module,exports){
var Config, JsNaclDriver, Keys, Nacl, Utils;

Keys = require('keys');

Utils = require('utils');

Config = require('config');

JsNaclDriver = require('js_nacl_driver');

Nacl = (function() {
  function Nacl() {}

  Nacl.API = ['crypto_secretbox_random_nonce', 'crypto_secretbox', 'crypto_secretbox_open', 'crypto_box', 'crypto_box_open', 'crypto_box_random_nonce', 'crypto_box_keypair', 'crypto_box_keypair_from_raw_sk', 'crypto_box_seed_keypair', 'crypto_box_keypair_from_seed', 'crypto_hash_sha256', 'random_bytes', 'encode_latin1', 'decode_latin1', 'encode_utf8', 'decode_utf8', 'to_hex', 'from_hex'];

  Nacl.prototype.naclImpl = null;

  Nacl.setNaclImpl = function(naclImpl) {
    return this.naclImpl = naclImpl;
  };

  Nacl.use = function() {
    if (!this.naclImpl) {
      this.setDefaultNaclImpl();
    }
    return this.naclImpl;
  };

  Nacl.setDefaultNaclImpl = function() {
    return this.naclImpl = new JsNaclDriver();
  };

  Nacl.makeSecretKey = function() {
    return this.use().random_bytes(this.use().crypto_secretbox_KEYBYTES).then(function(bytes) {
      return new Keys({
        key: bytes
      });
    });
  };

  Nacl.random = function(size) {
    if (size == null) {
      size = 32;
    }
    return this.use().random_bytes(size);
  };

  Nacl.makeKeyPair = function() {
    return this.use().crypto_box_keypair().then(function(kp) {
      return new Keys(kp);
    });
  };

  Nacl.fromSecretKey = function(raw_sk) {
    return this.use().crypto_box_keypair_from_raw_sk(raw_sk).then(function(kp) {
      return new Keys(kp);
    });
  };

  Nacl.fromSeed = function(seed) {
    return this.use().crypto_box_keypair_from_seed(seed).then(function(kp) {
      return new Keys(kp);
    });
  };

  Nacl.sha256 = function(data) {
    return this.use().crypto_hash_sha256(data);
  };

  Nacl.to_hex = function(data) {
    return this.use().to_hex(data);
  };

  Nacl.from_hex = function(data) {
    return this.use().from_hex(data);
  };

  Nacl.encode_latin1 = function(data) {
    return this.use().encode_latin1(data);
  };

  Nacl.decode_latin1 = function(data) {
    return this.use().decode_latin1(data);
  };

  Nacl.encode_utf8 = function(data) {
    return this.use().encode_utf8(data);
  };

  Nacl.decode_utf8 = function(data) {
    return this.use().decode_utf8(data);
  };

  Nacl.h2 = function(str) {
    var tmp;
    if (Utils.type(str) === 'String') {
      str = str.toUint8ArrayRaw();
    }
    tmp = new Uint8Array(32 + str.length);
    tmp.fillWith(0);
    tmp.set(str, 32);
    return this.sha256(tmp).then((function(_this) {
      return function(sha) {
        return _this.sha256(sha);
      };
    })(this));
  };

  Nacl.h2_64 = function(b64str) {
    return Nacl.h2(b64str.fromBase64()).then(function(h2) {
      return h2.toBase64();
    });
  };

  return Nacl;

})();

module.exports = Nacl;

if (window.__CRYPTO_DEBUG) {
  window.Nacl = Nacl;
}


},{"config":2,"js_nacl_driver":4,"keys":8,"utils":16}],13:[function(require,module,exports){
var KeyRatchet, KeyRing, Keys, Mailbox, Nacl, RatchetBox, Utils,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

Utils = require('utils');

Nacl = require('nacl');

Keys = require('keys');

KeyRing = require('keyring');

KeyRatchet = require('keyratchet');

Mailbox = require('mailbox');

RatchetBox = (function(superClass) {
  extend(RatchetBox, superClass);

  function RatchetBox() {
    return RatchetBox.__super__.constructor.apply(this, arguments);
  }

  RatchetBox.prototype._loadRatchets = function(guest) {
    return this._gHpk(guest).then((function(_this) {
      return function(gHpk) {
        gHpk = gHpk.toBase64();
        return KeyRatchet["new"]("local_" + gHpk + "_for_" + (_this.hpk().toBase64()), _this.keyRing, _this.keyRing.commKey).then(function(krLocal) {
          _this.krLocal = krLocal;
          return KeyRatchet["new"]("guest_" + gHpk + "_for_" + (_this.hpk().toBase64()), _this.keyRing, _this.keyRing.getGuestKey(guest)).then(function(krGuest) {
            return _this.krGuest = krGuest;
          });
        });
      };
    })(this));
  };

  RatchetBox.prototype.relaySend = function(relay, guest, m) {
    Utils.ensure(relay, guest, m);
    return this._loadRatchets(guest).then((function(_this) {
      return function() {
        var msg, pk;
        msg = {
          org_msg: m
        };
        if (!m.got_key) {
          msg['nextKey'] = _this.krLocal.nextKey.strPubKey();
        }
        pk = _this.krGuest[m.got_key ? 'lastKey' : 'confirmedKey'].boxPk;
        return _this.rawEncodeMessage(msg, pk, _this.krLocal.confirmedKey.boxSk).then(function(encMsg) {
          return Nacl.h2(_this._gPk(guest)).then(function(h2) {
            return relay.upload(_this, h2, encMsg);
          });
        });
      };
    })(this));
  };

  RatchetBox.prototype._tryKeypair = function(nonce, ctext, pk, sk) {
    var e;
    try {
      return this.rawDecodeMessage(nonce.fromBase64(), ctext.fromBase64(), pk, sk);
    } catch (error) {
      e = error;
      return Utils.resolve(null);
    }
  };

  RatchetBox.prototype.decodeMessage = function(guest, nonce, ctext, session, skTag) {
    if (session == null) {
      session = false;
    }
    if (skTag == null) {
      skTag = null;
    }
    if (session) {
      return RatchetBox.__super__.decodeMessage.call(this, guest, nonce, ctext, session, skTag);
    }
    Utils.ensure(guest, nonce, ctext);
    return this._loadRatchets(guest).then((function(_this) {
      return function() {
        var keyPairs;
        keyPairs = [[_this.krGuest.confirmedKey.boxPk, _this.krLocal.confirmedKey.boxSk], [_this.krGuest.lastKey.boxPk, _this.krLocal.lastKey.boxSk], [_this.krGuest.confirmedKey.boxPk, _this.krLocal.lastKey.boxSk], [_this.krGuest.lastKey.boxPk, _this.krLocal.confirmedKey.boxSk]];
        return Utils.serial(keyPairs, function(kp) {
          return _this._tryKeypair(nonce, ctext, kp[0], kp[1]);
        }).then(function(r) {
          if (!r) {
            console.log('RatchetBox decryption failed: message from ' + 'unknown guest or ratchet out of sync');
          }
          return r;
        });
      };
    })(this));
  };

  RatchetBox.prototype.relayMessages = function() {
    return RatchetBox.__super__.relayMessages.call(this).then((function(_this) {
      return function(download) {
        var sendConfs, tasks;
        sendConfs = [];
        return tasks = download.map(function(m) {
          if (!m.fromTag) {
            return;
          }
          _this._loadRatchets(m.fromTag).then(function() {
            var next, nextKey, ref;
            if ((ref = m.msg) != null ? ref.nextKey : void 0) {
              nextKey = new Keys({
                boxPk: m.msg.nextKey.fromBase64()
              });
              next = _this.krGuest.confKey(nextKey).then(function(res) {
                if (res) {
                  return Nacl.h2_64(m.msg.nextKey).then(function(h2) {
                    return sendConfs.push({
                      toTag: m.fromTag,
                      key: m.msg.nextKey,
                      msg: {
                        got_key: h2
                      }
                    });
                  });
                }
              });
            }
            return (next || Utils.resolve()).then(function() {
              var next2, ref1, ref2;
              if ((ref1 = m.msg) != null ? (ref2 = ref1.org_msg) != null ? ref2.got_key : void 0 : void 0) {
                m.msg = m.msg.org_msg;
                next2 = _this.krLocal.isNextKeyHash(m.msg.got_key.fromBase64()).then(function(isHash) {
                  if (isHash) {
                    return Nacl.makeKeyPair().then(function(kp) {
                      return _this.krLocal.pushKey(kp);
                    });
                  }
                }).then(function() {
                  return m.msg = null;
                });
              }
              return (next2 || Utils.resolve()).then(function() {
                if (m.msg) {
                  return m.msg = m.msg.org_msg;
                }
              });
            });
          });
          return Utils.all(tasks).then(function() {
            return Utils.serial(sendConfs, function(sc) {
              return _this.relaySend(sc.toTag, sc.msg).then(function() {
                return false;
              });
            });
          });
        });
      };
    })(this));
  };

  RatchetBox.prototype.selfDestruct = function(overseerAuthorized, withRatchet) {
    if (withRatchet == null) {
      withRatchet = false;
    }
    if (!overseerAuthorized) {
      return;
    }
    if (withRatchet) {
      return Utils.all(this.keyRing.registry.map((function(_this) {
        return function(guest) {
          return _this._loadRatchets(guest).then(function() {
            return _this.krLocal.selfDestruct(withRatchet).then(function() {
              return _this.krGuest.selfDestruct(withRatchet);
            });
          });
        };
      })(this))).then((function(_this) {
        return function() {
          return RatchetBox.__super__.selfDestruct.call(_this, overseerAuthorized);
        };
      })(this));
    }
  };

  return RatchetBox;

})(Mailbox);

module.exports = RatchetBox;

if (window.__CRYPTO_DEBUG) {
  window.RatchetBox = RatchetBox;
}


},{"keyratchet":6,"keyring":7,"keys":8,"mailbox":9,"nacl":12,"utils":16}],14:[function(require,module,exports){
var Config, EventEmitter, Keys, Nacl, Relay, Utils,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; },
  slice = [].slice;

Config = require('config');

Keys = require('keys');

Nacl = require('nacl');

Utils = require('utils');

EventEmitter = require('events').EventEmitter;

Relay = (function(superClass) {
  extend(Relay, superClass);

  function Relay(url) {
    this.url = url != null ? url : null;
    this._ajax = bind(this._ajax, this);
    this.retriesCount = 0;
    if (this.url && localStorage) {
      this.blockedTill = localStorage.getItem("blocked_" + this.url) || 0;
    }
    this._resetState();
    this.RELAY_COMMANDS = ['count', 'upload', 'download', 'messageStatus', 'delete', 'startFileUpload', 'uploadFileChunk', 'downloadFileChunk', 'fileStatus', 'deleteFile', 'getEntropy'];
  }

  Relay.prototype.openConnection = function() {
    return this.getServerToken().then((function(_this) {
      return function() {
        return _this.getServerKey();
      };
    })(this));
  };

  Relay.prototype.getServerToken = function() {
    var next;
    Utils.ensure(this.url);
    if (!this.clientToken) {
      next = Nacl.random(Config.RELAY_TOKEN_LEN).then((function(_this) {
        return function(clientToken) {
          return _this.clientToken = clientToken;
        };
      })(this));
    }
    return next = (next || Utils.resolve()).then((function(_this) {
      return function() {
        if (_this.clientToken && _this.clientToken.length !== Config.RELAY_TOKEN_LEN) {
          throw new Error("Token must be " + Config.RELAY_TOKEN_LEN + " bytes");
        }
        if (_this.clientTokenExpiration) {
          clearTimeout(_this.clientTokenExpiration);
        }
        return _this._request('start_session', _this.clientToken.toBase64()).then(function(data) {
          var lines;
          _this._scheduleExpireSession();
          lines = _this._processData(data);
          _this.relayToken = lines[0].fromBase64();
          if (lines.length !== 2) {
            throw new Error("Wrong start_session from " + _this.url);
          }
          _this.diff = parseInt(lines[1]);
          if (_this.diff > 10) {
            console.log("Relay " + _this.url + " requested difficulty " + _this.diff + ". Session handshake may take longer.");
          }
          if (_this.diff > 16) {
            console.log("Attempting handshake at difficulty " + _this.diff + "! This may take a while");
          }
          return data;
        });
      };
    })(this));
  };

  Relay.prototype.getServerKey = function() {
    Utils.ensure(this.url, this.clientToken, this.relayToken);
    return Nacl.h2(this.clientToken).then((function(_this) {
      return function(h2ClientToken) {
        var ensureNonceDiff, handshake, next;
        _this.h2ClientToken = h2ClientToken.toBase64();
        handshake = _this.clientToken.concat(_this.relayToken);
        if (_this.diff === 0) {
          next = Nacl.h2(handshake).then(function(h2) {
            return h2.toBase64();
          });
        } else {
          ensureNonceDiff = function() {
            return Nacl.random(32).then(function(nonce) {
              return Nacl.h2(handshake.concat(nonce)).then(function(h2) {
                if (Utils.arrayZeroBits(h2, _this.diff)) {
                  return nonce;
                }
                return ensureNonceDiff();
              });
            });
          };
          next = ensureNonceDiff().then(function(nonce) {
            return nonce.toBase64();
          });
        }
        return next.then(function(sessionHandshake) {
          return _this._request('verify_session', _this.h2ClientToken, sessionHandshake).then(function(d) {
            var relayPk;
            relayPk = d.fromBase64();
            _this.relayKey = new Keys({
              boxPk: relayPk
            });
            _this.online = true;
            delete _this.diff;
            return d;
          });
        });
      };
    })(this));
  };

  Relay.prototype.relayId = function() {
    Utils.ensure(this.url);
    return "relay_" + this.url;
  };

  Relay.prototype.connectMailbox = function(mbx) {
    var relayId;
    Utils.ensure(mbx, this.online, this.relayKey, this.url);
    relayId = this.relayId();
    return mbx.createSessionKey(relayId, true).then((function(_this) {
      return function(key) {
        return _this._request('prove', mbx, key.boxPk).then(function(d) {
          return relayId;
        });
      };
    })(this));
  };

  Relay.prototype.runCmd = function(cmd, mbx, params) {
    var data;
    if (params == null) {
      params = null;
    }
    Utils.ensure(cmd, mbx);
    if (indexOf.call(this.RELAY_COMMANDS, cmd) < 0) {
      throw new Error("Relay " + this.url + " doesn't support " + cmd);
    }
    data = {
      cmd: cmd
    };
    if (params) {
      data = Utils.extend(data, params);
    }
    return this._request('command', mbx, data).then((function(_this) {
      return function(d) {
        if (d == null) {
          throw new Error(_this.url + " - " + cmd + " error");
        }
        return _this._processResponse(d, mbx, cmd, params);
      };
    })(this))["catch"]((function(_this) {
      return function(err) {
        throw new Error(_this.url + " - " + cmd + " - " + err.message);
      };
    })(this));
  };

  Relay.prototype._request = function(type, param1, param2) {
    var clientTempPk, ctext, mbx, payload, request, sign;
    Utils.ensure(type, param1);
    if ((this.blockedTill != null) && this.blockedTill > Date.now()) {
      throw new Error('Relay disabled till ' + new Date(parseInt(this.blockedTill, 10)));
    }
    if (this.retriesCount >= Config.RELAY_RETRY_REQUEST_ATTEMPTS) {
      this.retriesCount = 0;
      this.blockedTill = Date.now() + Config.RELAY_BLOCKING_TIME;
      if (localStorage) {
        localStorage.setItem("blocked_" + this.url, this.blockedTill);
      }
      throw new Error('Relay out of reach');
    }
    switch (type) {
      case 'start_session':
        request = this._ajax('start_session', param1);
        break;
      case 'verify_session':
        request = this._ajax('verify_session', param1, param2);
        break;
      case 'prove':
        mbx = param1;
        clientTempPk = param2;
        mbx.keyRing.addTempGuest(this.relayId(), this.relayKey.strPubKey());
        delete this.relayKey;
        sign = clientTempPk.concat(this.relayToken).concat(this.clientToken);
        request = Nacl.h2(sign).then((function(_this) {
          return function(h2Sign) {
            return mbx.encodeMessage(_this.relayId(), h2Sign).then(function(inner) {
              inner['pub_key'] = mbx.keyRing.getPubCommKey();
              return mbx.encodeMessage(_this.relayId(), inner, true).then(function(outer) {
                return _this._ajax('prove', _this.h2ClientToken, clientTempPk.toBase64(), outer.nonce, outer.ctext);
              });
            });
          };
        })(this));
        break;
      case 'command':
        if (param2.cmd === 'uploadFileChunk') {
          ctext = param2.ctext;
          payload = Utils.extend({}, param2);
          delete payload.ctext;
          request = param1.encodeMessage(this.relayId(), payload, true).then((function(_this) {
            return function(message) {
              return _this._ajax('command', param1.hpk(), message.nonce, message.ctext, ctext);
            };
          })(this));
        } else {
          request = param1.encodeMessage(this.relayId(), param2, true).then((function(_this) {
            return function(message) {
              return _this._ajax('command', param1.hpk(), message.nonce, message.ctext);
            };
          })(this));
        }
        break;
      default:
        throw new Error("Unknown request type " + type);
    }
    return request.then((function(_this) {
      return function(data) {
        _this.retriesCount = 0;
        _this.blockedTill = 0;
        return data;
      };
    })(this))["catch"]((function(_this) {
      return function(err) {
        var ref, ref1;
        if ((ref = (ref1 = err.response) != null ? ref1.status : void 0) !== 401 && ref !== 500) {
          throw new Error('Bad Request');
        }
        _this.retriesCount++;
        _this._resetState();
        if (type === 'start_session') {
          return _this.getServerToken();
        } else if (type === 'verify_session') {
          return _this.openConnection();
        } else if (type === 'prove') {
          return _this.openConnection().then(function() {
            return _this.connectMailbox(param1);
          });
        } else {
          return _this.openConnection().then(function() {
            return _this.connectMailbox(param1).then(function() {
              return _this._request(type, param1, param2);
            });
          });
        }
      };
    })(this));
  };

  Relay.prototype._processResponse = function(d, mbx, cmd, params) {
    var ctext, datain, nonce;
    datain = this._processData(String(d));
    if (cmd === 'delete') {
      return JSON.parse(d);
    }
    if (cmd === 'upload') {
      if (!(datain.length === 1 && datain[0].length === Config.RELAY_TOKEN_B64)) {
        throw new Error(this.url + " - " + cmd + ": Bad response");
      }
      params.storage_token = d;
      return params;
    }
    if (cmd === 'messageStatus') {
      if (datain.length !== 1) {
        throw new Error(this.url + " - " + cmd + ": Bad response");
      }
      return parseInt(datain[0]);
    }
    if (cmd === 'downloadFileChunk') {
      if (datain.length !== 3) {
        throw new Error(this.url + " - " + cmd + ": Bad response");
      }
      nonce = datain[0];
      ctext = datain[1];
      return mbx.decodeMessage(this.relayId(), nonce, ctext, true).then((function(_this) {
        return function(response) {
          response = JSON.parse(response);
          response.ctext = datain[2];
          return response;
        };
      })(this));
    }
    if (datain.length !== 2) {
      throw new Error(this.url + " - " + cmd + ": Bad response");
    }
    nonce = datain[0];
    ctext = datain[1];
    if (cmd === 'startFileUpload' || cmd === 'fileStatus' || cmd === 'uploadFileChunk' || cmd === 'deleteFile') {
      return mbx.decodeMessage(this.relayId(), nonce, ctext, true).then((function(_this) {
        return function(response) {
          return JSON.parse(response);
        };
      })(this));
    } else {
      return mbx.decodeMessage(this.relayId(), nonce, ctext, true);
    }
  };

  Relay.prototype._processData = function(d) {
    var datain;
    datain = d.split('\r\n');
    if (!(datain.length >= 2)) {
      datain = d.split('\n');
    }
    return datain;
  };

  Relay.prototype._ajax = function() {
    var cmd, data;
    cmd = arguments[0], data = 2 <= arguments.length ? slice.call(arguments, 1) : [];
    return Utils.ajax(this.url + "/" + cmd, data.join('\r\n'));
  };

  Relay.prototype.count = function(mbx) {
    return this.runCmd('count', mbx);
  };

  Relay.prototype.upload = function(mbx, toHpk, payload) {
    return this.runCmd('upload', mbx, {
      to: toHpk.toBase64(),
      payload: payload
    });
  };

  Relay.prototype.messageStatus = function(mbx, storage_token) {
    return this.runCmd('messageStatus', mbx, {
      token: storage_token
    });
  };

  Relay.prototype.download = function(mbx) {
    return this.runCmd('download', mbx);
  };

  Relay.prototype["delete"] = function(mbx, nonceList) {
    return this.runCmd('delete', mbx, {
      payload: nonceList
    });
  };

  Relay.prototype.startFileUpload = function(mbx, toHpk, fileSize, metadata) {
    return this.runCmd('startFileUpload', mbx, {
      to: toHpk.toBase64(),
      file_size: fileSize,
      metadata: metadata
    });
  };

  Relay.prototype.uploadFileChunk = function(mbx, uploadID, part, totalParts, payload) {
    return this.runCmd('uploadFileChunk', mbx, {
      uploadID: uploadID,
      part: part,
      last_chunk: totalParts - 1 === part,
      nonce: payload.nonce,
      ctext: payload.ctext
    });
  };

  Relay.prototype.fileStatus = function(mbx, uploadID) {
    return this.runCmd('fileStatus', mbx, {
      uploadID: uploadID
    });
  };

  Relay.prototype.downloadFileChunk = function(mbx, uploadID, chunk) {
    return this.runCmd('downloadFileChunk', mbx, {
      uploadID: uploadID,
      part: chunk
    });
  };

  Relay.prototype.deleteFile = function(mbx, uploadID) {
    return this.runCmd('deleteFile', mbx, {
      uploadID: uploadID
    });
  };

  Relay.prototype._resetState = function() {
    this.clientToken = null;
    this.online = false;
    this.relayToken = null;
    this.relayKey = null;
    this.clientTokenExpiration = null;
    return this.clientTokenExpirationStart = 0;
  };

  Relay.prototype.timeToTokenExpiration = function() {
    return Math.max(Config.RELAY_TOKEN_TIMEOUT - (Date.now() - this.clientTokenExpirationStart), 0);
  };

  Relay.prototype.timeToSessionExpiration = function(mbx) {
    return mbx.timeToSessionExpiration(this.relayId());
  };

  Relay.prototype._scheduleExpireSession = function() {
    if (this.clientTokenExpiration) {
      clearTimeout(this.clientTokenExpiration);
    }
    this.clientTokenExpirationStart = Date.now();
    return this.clientTokenExpiration = setTimeout((function(_this) {
      return function() {
        _this._resetState();
        return _this.emit('relaytokentimeout');
      };
    })(this), Config.RELAY_TOKEN_TIMEOUT);
  };

  return Relay;

})(EventEmitter);

module.exports = Relay;

if (window.__CRYPTO_DEBUG) {
  window.Relay = Relay;
}


},{"config":2,"events":1,"keys":8,"nacl":12,"utils":16}],15:[function(require,module,exports){
var SimpleTestDriver, Utils;

Utils = require('utils');

SimpleTestDriver = (function() {
  SimpleTestDriver.prototype._state = null;

  SimpleTestDriver.prototype._key_tag = function(key) {
    return this._root_tag + "." + key;
  };

  function SimpleTestDriver(root, sourceData) {
    if (root == null) {
      root = 'storage.';
    }
    if (sourceData == null) {
      sourceData = null;
    }
    this._root_tag = "__glow." + root;
    this._load(sourceData);
  }

  SimpleTestDriver.prototype.get = function(key) {
    var res;
    if (!this._state) {
      this._load();
    }
    res = this._state[key] ? this._state[key] : JSON.parse(localStorage.getItem(this._key_tag(key)));
    return Utils.resolve(res);
  };

  SimpleTestDriver.prototype.set = function(key, value) {
    if (!this._state) {
      this._load();
    }
    this._state[key] = value;
    localStorage.setItem(this._key_tag(key), JSON.stringify(value));
    return this._persist();
  };

  SimpleTestDriver.prototype.multiSet = function(pairs) {
    var i, j, key, len;
    if (!this._state) {
      this._load();
    }
    for (i = j = 0, len = pairs.length; j < len; i = j += 2) {
      key = pairs[i];
      localStorage.setItem(this._key_tag(key), JSON.stringify(pairs[i + 1]));
    }
    return this._persist();
  };

  SimpleTestDriver.prototype.remove = function(key) {
    if (!this._state) {
      this._load();
    }
    delete this._state[key];
    localStorage.removeItem(this._key_tag(key));
    return this._persist();
  };

  SimpleTestDriver.prototype._persist = function() {
    return Utils.resolve();
  };

  SimpleTestDriver.prototype._load = function(sourceData) {
    if (sourceData == null) {
      sourceData = null;
    }
    this._state = sourceData ? sourceData : {};
    return console.log('INFO: SimpleTestDriver uses localStorage and should not be used in production for permanent key storage.');
  };

  return SimpleTestDriver;

})();

module.exports = SimpleTestDriver;


},{"utils":16}],16:[function(require,module,exports){
var Config, Utils;

Config = require('config');

Utils = (function() {
  function Utils() {}

  Utils.extend = function(target, source) {
    var key, val;
    if (typeof $ !== "undefined" && $ !== null ? $.extend : void 0) {
      return $.extend(target, source);
    } else {
      for (key in source) {
        val = source[key];
        if (source[key] !== void 0) {
          target[key] = source[key];
        }
      }
      return target;
    }
  };

  Utils.include = function(klass, mixin) {
    return this.extend(klass.prototype, mixin);
  };

  Utils.type = function(obj) {
    if (obj === void 0) {
      return 'undefined';
    }
    if (obj === null) {
      return 'null';
    }
    return Object.prototype.toString.call(obj).replace('[', '').replace(']', '').split(' ')[1];
  };

  Utils.ajaxImpl = null;

  Utils.setAjaxImpl = function(ajaxImpl) {
    return this.ajaxImpl = ajaxImpl;
  };

  Utils.ajax = function(url, data) {
    if (!this.ajaxImpl) {
      this.setDefaultAjaxImpl();
    }
    return this.ajaxImpl(url, data);
  };

  Utils.setDefaultAjaxImpl = function() {
    if (typeof axios !== "undefined" && axios !== null) {
      return this.setAjaxImpl(function(url, data) {
        return axios({
          url: url,
          method: 'post',
          headers: {
            'Accept': 'text/plain',
            'Content-Type': 'text/plain'
          },
          data: data,
          responseType: 'text',
          timeout: Config.RELAY_AJAX_TIMEOUT
        }).then(function(response) {
          return response.data;
        });
      });
    } else if ((typeof $ !== "undefined" && $ !== null ? $.ajax : void 0) && (typeof $ !== "undefined" && $ !== null ? $.Deferred : void 0)) {
      return this.setAjaxImpl(function(url, data) {
        return $.ajax({
          url: url,
          type: 'POST',
          dataType: 'text',
          timeout: Config.RELAY_AJAX_TIMEOUT,
          context: this,
          error: console.log,
          contentType: 'text/plain',
          data: data
        });
      });
    } else {
      throw new Error('Unable to set default Ajax implementation.');
    }
  };

  Utils.promiseImpl = null;

  Utils.setPromiseImpl = function(promiseImpl) {
    return this.promiseImpl = promiseImpl;
  };

  Utils.getPromiseImpl = function() {
    if (!this.promiseImpl) {
      this.setDefaultPromiseImpl();
    }
    return this.promiseImpl;
  };

  Utils.setDefaultPromiseImpl = function() {
    if (typeof Promise !== "undefined" && Promise !== null) {
      return this.setPromiseImpl({
        promise: function(resolver) {
          return new Promise(resolver);
        },
        all: function(arr) {
          return Promise.all(arr);
        }
      });
    } else {
      throw new Error('Unable to set default Promise implementation.');
    }
  };

  Utils.delay = function(milliseconds, func) {
    return setTimeout(func, milliseconds);
  };

  Utils.itoa = function(n) {
    var floor, i, lg, pw, ref, top;
    if (n <= 0) {
      return new Uint8Array((function() {
        var j, results;
        results = [];
        for (i = j = 0; j <= 7; i = ++j) {
          results.push(0);
        }
        return results;
      })());
    }
    ref = [Math.floor, Math.pow, Math.log], floor = ref[0], pw = ref[1], lg = ref[2];
    top = floor(lg(n) / lg(256));
    return new Uint8Array((function() {
      var j, ref1, results;
      results = [];
      for (i = j = ref1 = top; ref1 <= 0 ? j <= 0 : j >= 0; i = ref1 <= 0 ? ++j : --j) {
        results.push(floor(n / pw(256, i)) % 256);
      }
      return results;
    })());
  };

  Utils.atoi = function(a) {
    var i, j, l, len, sum, v;
    l = a.length - 1;
    sum = 0;
    for (i = j = 0, len = a.length; j < len; i = ++j) {
      v = a[i];
      sum += v * Math.pow(256, l - i);
    }
    return sum;
  };

  Utils.firstZeroBits = function(byte, n) {
    return byte === ((byte >> n) << n);
  };

  Utils.arrayZeroBits = function(arr, diff) {
    var a, i, j, ref, rmd;
    rmd = diff;
    for (i = j = 0, ref = 1 + diff / 8; 0 <= ref ? j <= ref : j >= ref; i = 0 <= ref ? ++j : --j) {
      a = arr[i];
      if (rmd <= 0) {
        return true;
      }
      if (rmd > 8) {
        rmd -= 8;
        if (a > 0) {
          return false;
        }
      } else {
        return this.firstZeroBits(a, rmd);
      }
    }
    return false;
  };

  Utils.resolve = function(value) {
    return this.getPromiseImpl().promise(function(res, rej) {
      return res(value);
    });
  };

  Utils.reject = function(error) {
    return this.getPromiseImpl().promise(function(res, rej) {
      return rej(error);
    });
  };

  Utils.promise = function(resolver) {
    return this.getPromiseImpl().promise(resolver);
  };

  Utils.all = function(promises) {
    return this.getPromiseImpl().all(promises);
  };

  Utils.serial = function(arr, promiseFunc) {
    var i, iter;
    i = 0;
    iter = (function(_this) {
      return function(elem) {
        return promiseFunc(elem).then(function(res) {
          if (res) {
            return res;
          }
          if (i < arr.length) {
            return iter(arr[++i]);
          }
        });
      };
    })(this);
    return iter(arr[++i]);
  };

  Utils.ENSURE_ERROR_MSG = 'invalid arguments';

  Utils.ensure = function() {
    var a, j, len, results;
    results = [];
    for (j = 0, len = arguments.length; j < len; j++) {
      a = arguments[j];
      if (!a) {
        throw new Error(Utils.ENSURE_ERROR_MSG);
      } else {
        results.push(void 0);
      }
    }
    return results;
  };

  return Utils;

})();

module.exports = Utils;

if (window.__CRYPTO_DEBUG) {
  window.Utils = Utils;
}


},{"config":2}]},{},[10])
//# sourceMappingURL=theglow.js.map
