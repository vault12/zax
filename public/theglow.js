(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(require,module,exports){
var Config;

Config = (function() {
  function Config() {}

  Config._NONCE_TAG = '__nc';

  Config._SKEY_TAG = 'storage_key';

  Config._DEF_ROOT = '.v1.stor.vlt12';

  Config.RELAY_TOKEN_LEN = 32;

  Config.RELAY_TOKEN_TIMEOUT = 60 * 1000;

  Config.RELAY_SESSION_TIMEOUT = 5 * 60 * 1000;

  Config.RELAY_AJAX_TIMEOUT = 5 * 1000;

  return Config;

})();

module.exports = Config;


},{}],2:[function(require,module,exports){
var Config, CryptoStorage, Keys, Nacl;

Config = require('config');

Keys = require('keys');

Nacl = require('nacl');

CryptoStorage = (function() {
  CryptoStorage.prototype.tag = function(strKey) {
    return strKey && strKey + this.root;
  };

  function CryptoStorage(storageKey, r) {
    this.storageKey = storageKey != null ? storageKey : null;
    if (r == null) {
      r = null;
    }
    this.root = r ? "." + r + Config._DEF_ROOT : Config._DEF_ROOT;
    if (!this.storageKey) {
      this._loadKey();
    }
    if (!this.storageKey) {
      this.newKey();
    }
  }

  CryptoStorage.prototype._saveKey = function() {
    return this._set(Config._SKEY_TAG, this.storageKey.toString());
  };

  CryptoStorage.prototype._loadKey = function() {
    var keyStr;
    keyStr = this._get(Config._SKEY_TAG);
    if (keyStr) {
      return this.setKey(Keys.fromString(keyStr));
    }
  };

  CryptoStorage.prototype.selfDestruct = function(overseerAuthorized) {
    if (overseerAuthorized) {
      return this._localRemove(this.tag(Config._SKEY_TAG));
    }
  };

  CryptoStorage.prototype.setKey = function(objStorageKey) {
    this.storageKey = objStorageKey;
    return this._saveKey();
  };

  CryptoStorage.prototype.newKey = function() {
    return this.setKey(Nacl.makeSecretKey());
  };

  CryptoStorage.prototype.save = function(strTag, data) {
    var aCText, n, nonce;
    if (!(strTag && data)) {
      return null;
    }
    n = Nacl.use();
    data = n.encode_utf8(JSON.stringify(data));
    nonce = n.crypto_secretbox_random_nonce();
    aCText = n.crypto_secretbox(data, nonce, this.storageKey.key);
    this._set(strTag, aCText.toBase64());
    this._set(Config._NONCE_TAG + "." + strTag, nonce.toBase64());
    return true;
  };

  CryptoStorage.prototype.get = function(strTag) {
    var aPText, ct, n, nonce;
    ct = this._get(strTag);
    if (!ct) {
      return null;
    }
    nonce = this._get(Config._NONCE_TAG + "." + strTag);
    if (!nonce) {
      return null;
    }
    n = Nacl.use();
    aPText = n.crypto_secretbox_open(ct.fromBase64(), nonce.fromBase64(), this.storageKey.key);
    return JSON.parse(n.decode_utf8(aPText));
  };

  CryptoStorage.prototype.remove = function(strTag) {
    var i, len, ref, tag;
    ref = [strTag, Config._NONCE_TAG + "." + strTag];
    for (i = 0, len = ref.length; i < len; i++) {
      tag = ref[i];
      this._localRemove(this.tag(tag));
    }
    return true;
  };

  CryptoStorage.prototype._get = function(strTag) {
    return this._localGet(this.tag(strTag));
  };

  CryptoStorage.prototype._set = function(strTag, strData) {
    if (!(strTag && strData)) {
      return null;
    }
    this._localSet(this.tag(strTag), strData);
    return strData;
  };

  CryptoStorage.prototype._localGet = function(str) {
    return this._storage().get(str) || null;
  };

  CryptoStorage.prototype._localSet = function(str, data) {
    return this._storage().set(str, data);
  };

  CryptoStorage.prototype._localRemove = function(str) {
    return this._storage().remove(str);
  };

  CryptoStorage.prototype._storage = function() {
    if (!CryptoStorage._storageDriver) {
      CryptoStorage.startStorageSystem();
    }
    return CryptoStorage._storageDriver;
  };

  CryptoStorage._storageDriver = null;

  CryptoStorage.startStorageSystem = function(driver) {
    if (!driver) {
      throw new Error('The driver parameter cannot be empty.');
    }
    return this._storageDriver = driver;
  };

  return CryptoStorage;

})();

module.exports = CryptoStorage;


},{"config":1,"keys":5,"nacl":9}],3:[function(require,module,exports){
var KeyRatchet, Nacl;

Nacl = require('nacl');

KeyRatchet = (function() {
  KeyRatchet.prototype.lastKey = null;

  KeyRatchet.prototype.confirmedKey = null;

  KeyRatchet.prototype.nextKey = null;

  KeyRatchet.prototype._roles = ['lastKey', 'confirmedKey', 'nextKey'];

  function KeyRatchet(id, keyRing, firstKey) {
    var i, len, ref, s;
    this.id = id;
    this.keyRing = keyRing;
    if (firstKey == null) {
      firstKey = null;
    }
    if (!(this.id && this.keyRing)) {
      throw new Error('KeyRatchet - missing params');
    }
    ref = this._roles;
    for (i = 0, len = ref.length; i < len; i++) {
      s = ref[i];
      this[s] = this.keyRing.getKey(this.keyTag(s));
    }
    if (firstKey) {
      this.startRatchet(firstKey);
    }
  }

  KeyRatchet.prototype.keyTag = function(role) {
    return role + "_" + this.id;
  };

  KeyRatchet.prototype.storeKey = function(role) {
    return this.keyRing.saveKey(this.keyTag(role), this[role]);
  };

  KeyRatchet.prototype.startRatchet = function(firstKey) {
    var i, k, len, ref;
    ref = ['confirmedKey', 'lastKey'];
    for (i = 0, len = ref.length; i < len; i++) {
      k = ref[i];
      if (!this[k]) {
        this[k] = firstKey;
        this.storeKey(k);
      }
    }
    if (!this.nextKey) {
      this.nextKey = Nacl.makeKeyPair();
      return this.storeKey('nextKey');
    }
  };

  KeyRatchet.prototype.pushKey = function(newKey) {
    var i, len, ref, results, s;
    this.lastKey = this.confirmedKey;
    this.confirmedKey = this.nextKey;
    this.nextKey = newKey;
    ref = this._roles;
    results = [];
    for (i = 0, len = ref.length; i < len; i++) {
      s = ref[i];
      results.push(this.storeKey(s));
    }
    return results;
  };

  KeyRatchet.prototype.confKey = function(newConfirmedKey) {
    var i, len, ref, s;
    if ((this.confirmedKey != null) && this.confirmedKey.equal(newConfirmedKey)) {
      return false;
    }
    this.lastKey = this.confirmedKey;
    this.confirmedKey = newConfirmedKey;
    ref = ['lastKey', 'confirmedKey'];
    for (i = 0, len = ref.length; i < len; i++) {
      s = ref[i];
      this.storeKey(s);
    }
    return true;
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
    var i, len, ref, s;
    ref = this._roles;
    for (i = 0, len = ref.length; i < len; i++) {
      s = ref[i];
      if (Nacl.h2(this[s].boxPk) === hash) {
        return this[s];
      }
    }
  };

  KeyRatchet.prototype.isNextKeyHash = function(hash) {
    return this.h2NextKey().equal(hash);
  };

  KeyRatchet.prototype.toStr = function() {
    return JSON.stringify(this).toBase64();
  };

  KeyRatchet.prototype.fromStr = function(str) {
    return Utils.extend(this, JSON.parse(str.fromBase64()));
  };

  KeyRatchet.prototype.selfDestruct = function(overseerAuthorized) {
    var i, len, ref, results, s;
    if (!overseerAuthorized) {
      return null;
    }
    ref = this._roles;
    results = [];
    for (i = 0, len = ref.length; i < len; i++) {
      s = ref[i];
      results.push(this.keyRing.deleteKey(this.keyTag(s)));
    }
    return results;
  };

  return KeyRatchet;

})();

module.exports = KeyRatchet;

if (window.__CRYPTO_DEBUG) {
  window.KeyRatchet = KeyRatchet;
}


},{"nacl":9}],4:[function(require,module,exports){
var Config, CryptoStorage, KeyRing, Keys, Nacl, Utils,
  hasProp = {}.hasOwnProperty;

Config = require('config');

CryptoStorage = require('crypto_storage');

Keys = require('keys');

Nacl = require('nacl');

Utils = require('utils');

KeyRing = (function() {
  function KeyRing(id, strMasterKey) {
    var key;
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    if (strMasterKey) {
      key = Keys.fromString(strMasterKey);
      this.storage = new CryptoStorage(key, id);
    }
    if (!this.storage) {
      this.storage = new CryptoStorage(null, id);
    }
    this._ensureKeys();
  }

  KeyRing.prototype._ensureKeys = function() {
    this._loadCommKey();
    return this._loadGuestKeys();
  };

  KeyRing.prototype._loadCommKey = function() {
    this.commKey = this.getKey('comm_key');
    if (this.commKey) {
      return;
    }
    this.commKey = Nacl.makeKeyPair();
    return this.saveKey('comm_key', this.commKey);
  };

  KeyRing.prototype._loadGuestKeys = function() {
    var j, len, r, ref, results;
    this.registry = this.storage.get('guest_registry') || [];
    this.guestKeys = {};
    ref = this.registry;
    results = [];
    for (j = 0, len = ref.length; j < len; j++) {
      r = ref[j];
      results.push(this.guestKeys[r] = this.storage.get("guest[" + r + "]"));
    }
    return results;
  };

  KeyRing.prototype.commFromSeed = function(seed) {
    this.commKey = Nacl.fromSeed(Nacl.encode_utf8(seed));
    return this.storage.save('comm_key', this.commKey.toString());
  };

  KeyRing.prototype.commFromSecKey = function(rawSecKey) {
    this.commKey = Nacl.fromSecretKey(rawSecKey);
    return this.storage.save('comm_key', this.commKey.toString());
  };

  KeyRing.prototype.tagByHpk = function(hpk) {
    var k, ref, v;
    ref = this.guestKeys;
    for (k in ref) {
      if (!hasProp.call(ref, k)) continue;
      v = ref[k];
      if (hpk === Nacl.h2(v.fromBase64()).toBase64()) {
        return k;
      }
    }
  };

  KeyRing.prototype.getMasterKey = function() {
    return this.storage.storageKey.key2str('key');
  };

  KeyRing.prototype.getPubCommKey = function() {
    return this.commKey.strPubKey();
  };

  KeyRing.prototype.saveKey = function(tag, key) {
    this.storage.save(tag, key.toString());
    return key;
  };

  KeyRing.prototype.getKey = function(tag) {
    var k;
    k = this.storage.get(tag);
    if (k) {
      return Keys.fromString(k);
    } else {
      return null;
    }
  };

  KeyRing.prototype.deleteKey = function(tag) {
    return this.storage.remove(tag);
  };

  KeyRing.prototype._addRegistry = function(strGuestTag) {
    if (!strGuestTag) {
      return null;
    }
    if (!(this.registry.indexOf(strGuestTag) > -1)) {
      return this.registry.push(strGuestTag);
    }
  };

  KeyRing.prototype._saveNewGuest = function(tag, pk) {
    if (!(tag && pk)) {
      return null;
    }
    this.storage.save("guest[" + tag + "]", pk);
    return this.storage.save('guest_registry', this.registry);
  };

  KeyRing.prototype._removeGuestRecord = function(tag) {
    var i;
    if (!tag) {
      return null;
    }
    this.storage.remove("guest[" + tag + "]");
    i = this.registry.indexOf(tag);
    if (i > -1) {
      this.registry.splice(i, 1);
      return this.storage.save('guest_registry', this.registry);
    }
  };

  KeyRing.prototype.addGuest = function(strGuestTag, b64_pk) {
    if (!(strGuestTag && b64_pk)) {
      return null;
    }
    b64_pk = b64_pk.trimLines();
    this._addRegistry(strGuestTag);
    this.guestKeys[strGuestTag] = b64_pk;
    return this._saveNewGuest(strGuestTag, b64_pk);
  };

  KeyRing.prototype.addTempGuest = function(strGuestTag, strPubKey) {
    if (!(strGuestTag && strPubKey)) {
      return null;
    }
    strPubKey = strPubKey.trimLines();
    this.guestKeys[strGuestTag] = strPubKey;
    return Utils.delay(Config.RELAY_SESSION_TIMEOUT, (function(_this) {
      return function() {
        return delete _this.guestKeys[strGuestTag];
      };
    })(this));
  };

  KeyRing.prototype.removeGuest = function(strGuestTag) {
    if (!(strGuestTag && this.guestKeys[strGuestTag])) {
      return null;
    }
    this.guestKeys[strGuestTag] = null;
    delete this.guestKeys[strGuestTag];
    return this._removeGuestRecord(strGuestTag);
  };

  KeyRing.prototype.getGuestKey = function(strGuestTag) {
    if (!(strGuestTag && this.guestKeys[strGuestTag])) {
      return null;
    }
    return new Keys({
      boxPk: this.getGuestRecord(strGuestTag).fromBase64()
    });
  };

  KeyRing.prototype.getGuestRecord = function(strGuestTag) {
    if (!(strGuestTag && this.guestKeys[strGuestTag])) {
      return null;
    }
    return this.guestKeys[strGuestTag];
  };

  KeyRing.prototype.selfDestruct = function(overseerAuthorized) {
    var g, j, len, rcopy;
    if (!overseerAuthorized) {
      return null;
    }
    rcopy = this.registry.slice();
    for (j = 0, len = rcopy.length; j < len; j++) {
      g = rcopy[j];
      this.removeGuest(g);
    }
    this.storage.remove('guest_registry');
    this.storage.remove('comm_key');
    return this.storage.selfDestruct(overseerAuthorized);
  };

  return KeyRing;

})();

module.exports = KeyRing;

if (window.__CRYPTO_DEBUG) {
  window.KeyRing = KeyRing;
}


},{"config":1,"crypto_storage":2,"keys":5,"nacl":9,"utils":13}],5:[function(require,module,exports){
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


},{"utils":13}],6:[function(require,module,exports){
var Config, KeyRing, MailBox, Nacl, Utils;

Config = require('config');

KeyRing = require('keyring');

Nacl = require('nacl');

Utils = require('utils');

MailBox = (function() {
  function MailBox(identity, strMasterKey) {
    this.identity = identity;
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    this.keyRing = new KeyRing(this.identity, strMasterKey);
    this.sessionKeys = {};
    this.sessionRelay = {};
    this.sessionTimeout = {};
  }

  MailBox.fromSeed = function(seed, id, strMasterKey) {
    var mbx;
    if (id == null) {
      id = seed;
    }
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    mbx = new MailBox(id, strMasterKey);
    mbx.keyRing.commFromSeed(seed);
    mbx._hpk = null;
    return mbx;
  };

  MailBox.fromSecKey = function(secKey, id, strMasterKey) {
    var mbx;
    if (strMasterKey == null) {
      strMasterKey = null;
    }
    mbx = new MailBox(id, strMasterKey);
    mbx.keyRing.commFromSecKey(secKey);
    mbx._hpk = null;
    return mbx;
  };

  MailBox.prototype.hpk = function() {
    if (this._hpk) {
      return this._hpk;
    }
    return this._hpk = Nacl.h2(this.keyRing.commKey.boxPk);
  };

  MailBox.prototype.getPubCommKey = function() {
    return this.keyRing.getPubCommKey();
  };

  MailBox.prototype.createSessionKey = function(sess_id) {
    if (!sess_id) {
      throw new Error('createSessionKey - no sess_id');
    }
    if (this.sessionKeys[sess_id] != null) {
      return this.sessionKeys[sess_id];
    }
    this.sessionKeys[sess_id] = Nacl.makeKeyPair();
    this.sessionTimeout[sess_id] = Utils.delay(Config.RELAY_SESSION_TIMEOUT, (function(_this) {
      return function() {
        _this.sessionKeys[sess_id] = null;
        delete _this.sessionKeys[sess_id];
        _this.sessionTimeout[sess_id] = null;
        delete _this.sessionTimeout[sess_id];
        _this.sessionRelay[sess_id] = null;
        return delete _this.sessionRelay[sess_id];
      };
    })(this));
    return this.sessionKeys[sess_id];
  };

  MailBox.prototype.rawEncodeMessage = function(msg, pkTo, skFrom) {
    var nonce, r;
    if (!((msg != null) && (pkTo != null) && (skFrom != null))) {
      throw new Error('rawEncodeMessage: missing params');
    }
    nonce = this._makeNonce();
    return r = {
      nonce: nonce.toBase64(),
      ctext: Nacl.use().crypto_box(this._parseData(msg), nonce, pkTo, skFrom).toBase64()
    };
  };

  MailBox.prototype.rawDecodeMessage = function(nonce, ctext, pkFrom, skTo) {
    var NC;
    if (!((nonce != null) && (ctext != null) && (pkFrom != null) && (skTo != null))) {
      throw new Error('rawEncodeMessage: missing params');
    }
    NC = Nacl.use();
    return JSON.parse(NC.decode_utf8(NC.crypto_box_open(ctext, nonce, pkFrom, skTo)));
  };

  MailBox.prototype.encodeMessage = function(guest, msg, session, skTag) {
    var gpk, sk;
    if (session == null) {
      session = false;
    }
    if (skTag == null) {
      skTag = null;
    }
    if (!((guest != null) && (msg != null))) {
      throw new Error('encodeMessage: missing params');
    }
    if ((gpk = this._gPk(guest)) == null) {
      throw new Error("encodeMessage: don't know guest " + guest);
    }
    sk = this._getSecretKey(guest, session, skTag);
    return this.rawEncodeMessage(msg, gpk, sk);
  };

  MailBox.prototype.decodeMessage = function(guest, nonce, ctext, session, skTag) {
    var gpk, sk;
    if (session == null) {
      session = false;
    }
    if (skTag == null) {
      skTag = null;
    }
    if (!((guest != null) && (nonce != null) && (ctext != null))) {
      throw new Error('decodeMessage: missing params');
    }
    if ((gpk = this._gPk(guest)) == null) {
      throw new Error("decodeMessage: don't know guest " + guest);
    }
    sk = this._getSecretKey(guest, session, skTag);
    return this.rawDecodeMessage(nonce.fromBase64(), ctext.fromBase64(), gpk, sk);
  };

  MailBox.prototype.connectToRelay = function(relay) {
    return relay.openConnection().then((function(_this) {
      return function() {
        return relay.connectMailbox(_this).then(function() {
          return _this.lastRelay = relay;
        });
      };
    })(this));
  };

  MailBox.prototype.sendToVia = function(guest, relay, msg) {
    return this.connectToRelay(relay).then((function(_this) {
      return function() {
        return _this.relaySend(guest, msg, relay);
      };
    })(this));
  };

  MailBox.prototype.getRelayMessages = function(relay) {
    return this.connectToRelay(relay).then((function(_this) {
      return function() {
        return _this.relayMessages();
      };
    })(this));
  };

  MailBox.prototype.relayCount = function() {
    if (!this.lastRelay) {
      throw new Error('relayCount - no open relay');
    }
    return this.lastRelay.count(this).then((function(_this) {
      return function() {
        return _this.count = parseInt(_this.lastRelay.result);
      };
    })(this));
  };

  MailBox.prototype.relaySend = function(guest, msg) {
    var encMsg;
    if (!this.lastRelay) {
      throw new Error('mbx: relaySend - no open relay');
    }
    encMsg = this.encodeMessage(guest, msg);
    this.lastMsg = encMsg;
    return this.lastRelay.upload(this, Nacl.h2(this._gPk(guest)), encMsg);
  };

  MailBox.prototype.relayMessages = function() {
    if (!this.lastRelay) {
      throw new Error('relayMessages - no open relay');
    }
    return this.lastRelay.download(this).then((function(_this) {
      return function() {
        var emsg, j, len, ref, results, tag;
        _this.lastDownload = [];
        ref = _this.lastRelay.result;
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          emsg = ref[j];
          if ((tag = _this.keyRing.tagByHpk(emsg.from))) {
            emsg['fromTag'] = tag;
            emsg['msg'] = _this.decodeMessage(tag, emsg.nonce, emsg.data);
            if (emsg['msg'] != null) {
              delete emsg.data;
            }
          }
          results.push(_this.lastDownload.push(emsg));
        }
        return results;
      };
    })(this));
  };

  MailBox.prototype.relayNonceList = function() {
    if (!this.lastDownload) {
      throw new Error('relayNonceList - no metadata');
    }
    return Utils.map(this.lastDownload, function(i) {
      return i.nonce;
    });
  };

  MailBox.prototype.relayDelete = function(list) {
    if (!this.lastRelay) {
      throw new Error('relayDelete - no open relay');
    }
    return this.lastRelay["delete"](this, list);
  };

  MailBox.prototype.clean = function(r) {
    return this.getRelayMessages(r).then((function(_this) {
      return function() {
        return _this.relayDelete(_this.relayNonceList());
      };
    })(this));
  };

  MailBox.prototype.selfDestruct = function(overseerAuthorized) {
    if (!overseerAuthorized) {
      return null;
    }
    return this.keyRing.selfDestruct(overseerAuthorized);
  };

  MailBox.prototype._gKey = function(strId) {
    if (!strId) {
      return null;
    }
    return this.keyRing.getGuestKey(strId);
  };

  MailBox.prototype._gPk = function(strId) {
    var ref;
    if (!strId) {
      return null;
    }
    return (ref = this._gKey(strId)) != null ? ref.boxPk : void 0;
  };

  MailBox.prototype._gHpk = function(strId) {
    if (!strId) {
      return null;
    }
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
      return data;
    }
    return Nacl.use().encode_utf8(JSON.stringify(data));
  };

  MailBox.prototype._makeNonce = function(time) {
    var bytes, i, j, k, nonce, ref;
    if (time == null) {
      time = parseInt(Date.now() / 1000);
    }
    nonce = Nacl.use().crypto_box_random_nonce();
    if (!((nonce != null) && nonce.length === 24)) {
      throw new Error('RNG failed, try again?');
    }
    bytes = Utils.itoa(time);
    for (i = j = 0; j <= 7; i = ++j) {
      nonce[i] = 0;
    }
    for (i = k = 0, ref = bytes.length - 1; 0 <= ref ? k <= ref : k >= ref; i = 0 <= ref ? ++k : --k) {
      nonce[8 - bytes.length + i] = bytes[i];
    }
    return nonce;
  };

  return MailBox;

})();

module.exports = MailBox;

if (window.__CRYPTO_DEBUG) {
  window.MailBox = MailBox;
}


},{"config":1,"keyring":4,"nacl":9,"utils":13}],7:[function(require,module,exports){
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


},{"config":1,"crypto_storage":2,"keyring":4,"keys":5,"mailbox":6,"mixins":8,"nacl":9,"rachetbox":10,"relay":11,"test_driver":12,"utils":13}],8:[function(require,module,exports){
var C, Utils, j, len, ref;

Utils = require('utils');

Utils.include(String, {
  toCodeArray: function() {
    var j, len, results, s;
    results = [];
    for (j = 0, len = this.length; j < len; j++) {
      s = this[j];
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
        var k, len1, results;
        results = [];
        for (k = 0, len1 = this.length; k < len1; k++) {
          c = this[k];
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
        var k, len1, results;
        results = [];
        for (i = k = 0, len1 = this.length; k < len1; i = ++k) {
          c = this[i];
          results.push(c ^ a[i]);
        }
        return results;
      }).call(this));
    },
    equal: function(a2) {
      var i, k, len1, v;
      if (this.length !== a2.length) {
        return false;
      }
      for (i = k = 0, len1 = this.length; k < len1; i = ++k) {
        v = this[i];
        if (v !== a2[i]) {
          return false;
        }
      }
      return true;
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
    var i, k, len1, v;
    for (i = k = 0, len1 = this.length; k < len1; i = ++k) {
      v = this[i];
      this[i] = val;
    }
    return this;
  }
});

module.exports = {};


},{"utils":13}],9:[function(require,module,exports){
var Keys, Nacl, Utils, js_nacl;

if (typeof nacl_factory !== "undefined" && nacl_factory !== null) {
  js_nacl = nacl_factory;
} else {
  js_nacl = require('js-nacl');
}

Keys = require('keys');

Utils = require('utils');

Nacl = (function() {
  function Nacl() {}

  Nacl.HEAP_SIZE = Math.pow(2, 23);

  Nacl._instance = null;

  Nacl._unloadTimer = null;

  Nacl.use = function() {
    if (this._unloadTimer) {
      clearTimeout(this._unloadTimer);
    }
    this._unloadTimer = setTimeout((function() {
      return Nacl.unload();
    }), 15 * 1000);
    if (!window.__naclInstance) {
      window.__naclInstance = js_nacl.instantiate(this.HEAP_SIZE);
    }
    return window.__naclInstance;
  };

  Nacl.unload = function() {
    this._unloadTimer = null;
    window.__naclInstance = null;
    return delete window.__naclInstance;
  };

  Nacl.makeSecretKey = function() {
    return new Keys({
      key: this.use().random_bytes(this.use().crypto_secretbox_KEYBYTES)
    });
  };

  Nacl.random = function(size) {
    if (size == null) {
      size = 32;
    }
    return this.use().random_bytes(size);
  };

  Nacl.makeKeyPair = function() {
    return new Keys(this.use().crypto_box_keypair());
  };

  Nacl.fromSecretKey = function(raw_sk) {
    return new Keys(this.use().crypto_box_keypair_from_raw_sk(raw_sk));
  };

  Nacl.fromSeed = function(seed) {
    return new Keys(this.use().crypto_box_keypair_from_seed(seed));
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
    return this.sha256(this.sha256(tmp));
  };

  Nacl.h2_64 = function(b64str) {
    return Nacl.h2(b64str.fromBase64()).toBase64();
  };

  return Nacl;

})();

module.exports = Nacl;

if (window.__CRYPTO_DEBUG) {
  window.Nacl = Nacl;
}


},{"js-nacl":undefined,"keys":5,"utils":13}],10:[function(require,module,exports){
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
    var gHpk;
    gHpk = this._gHpk(guest).toBase64();
    this.krLocal = new KeyRatchet("local_" + gHpk + "_for_" + (this.hpk().toBase64()), this.keyRing, this.keyRing.commKey);
    return this.krGuest = new KeyRatchet("guest_" + gHpk + "_for_" + (this.hpk().toBase64()), this.keyRing, this.keyRing.getGuestKey(guest));
  };

  RatchetBox.prototype.relaySend = function(guest, m) {
    var encMsg, msg;
    if (!this.lastRelay) {
      throw new Error('rbx: relaySend - no open relay');
    }
    if (!(guest && m)) {
      throw new Error('rbx: relaySend - missing params');
    }
    this._loadRatchets(guest);
    msg = {
      org_msg: m
    };
    if (m.got_key == null) {
      msg['nextKey'] = this.krLocal.nextKey.strPubKey();
    }
    if (m.got_key == null) {
      encMsg = this.rawEncodeMessage(msg, this.krGuest.confirmedKey.boxPk, this.krLocal.confirmedKey.boxSk);
      this.lastMsg = encMsg;
    } else {
      encMsg = this.rawEncodeMessage(msg, this.krGuest.lastKey.boxPk, this.krLocal.confirmedKey.boxSk);
    }
    return this.lastRelay.upload(this, Nacl.h2(this._gPk(guest)), encMsg);
  };

  RatchetBox.prototype._tryKeypair = function(nonce, ctext, pk, sk) {
    var e, error;
    try {
      return this.rawDecodeMessage(nonce.fromBase64(), ctext.fromBase64(), pk, sk);
    } catch (error) {
      e = error;
      return null;
    }
  };

  RatchetBox.prototype.decodeMessage = function(guest, nonce, ctext, session, skTag) {
    var i, j, keyPairs, kp, len, r;
    if (session == null) {
      session = false;
    }
    if (skTag == null) {
      skTag = null;
    }
    if (session) {
      return RatchetBox.__super__.decodeMessage.call(this, guest, nonce, ctext, session, skTag);
    }
    if (!((guest != null) && (nonce != null) && (ctext != null))) {
      throw new Error('decodeMessage: missing params');
    }
    this._loadRatchets(guest);
    keyPairs = [[this.krGuest.confirmedKey.boxPk, this.krLocal.confirmedKey.boxSk], [this.krGuest.lastKey.boxPk, this.krLocal.lastKey.boxSk], [this.krGuest.confirmedKey.boxPk, this.krLocal.lastKey.boxSk], [this.krGuest.lastKey.boxPk, this.krLocal.confirmedKey.boxSk]];
    for (i = j = 0, len = keyPairs.length; j < len; i = ++j) {
      kp = keyPairs[i];
      r = this._tryKeypair(nonce, ctext, kp[0], kp[1]);
      if (r != null) {
        return r;
      }
    }
    console.log('RatchetBox decryption failed: message from unknown guest or ratchet out of sync');
    return null;
  };

  RatchetBox.prototype.relayMessages = function() {
    return RatchetBox.__super__.relayMessages.call(this).then((function(_this) {
      return function() {
        var j, len, m, ref, ref1, ref2, ref3, sendConfs, sendNext;
        sendConfs = [];
        ref = _this.lastDownload;
        for (j = 0, len = ref.length; j < len; j++) {
          m = ref[j];
          if (!m.fromTag) {
            continue;
          }
          _this._loadRatchets(m.fromTag);
          if (((ref1 = m.msg) != null ? ref1.nextKey : void 0) != null) {
            if (_this.krGuest.confKey(new Keys({
              boxPk: m.msg.nextKey.fromBase64()
            }))) {
              sendConfs.push({
                toTag: m.fromTag,
                key: m.msg.nextKey,
                msg: {
                  got_key: Nacl.h2_64(m.msg.nextKey)
                }
              });
            }
          }
          if (((ref2 = m.msg) != null ? (ref3 = ref2.org_msg) != null ? ref3.got_key : void 0 : void 0) != null) {
            m.msg = m.msg.org_msg;
            if (_this.krLocal.isNextKeyHash(m.msg.got_key.fromBase64())) {
              _this.krLocal.pushKey(Nacl.makeKeyPair());
            }
            m.msg = null;
          }
          if (m.msg != null) {
            m.msg = m.msg.org_msg;
          }
        }
        sendNext = function() {
          var sc;
          if (sendConfs.length > 0) {
            sc = sendConfs.shift();
            return _this.relaySend(sc.toTag, sc.msg).then(function() {
              return sendNext();
            });
          }
        };
        return sendNext();
      };
    })(this));
  };

  RatchetBox.prototype.selfDestruct = function(overseerAuthorized, withRatchet) {
    var guest, j, len, ref;
    if (withRatchet == null) {
      withRatchet = false;
    }
    if (!overseerAuthorized) {
      return;
    }
    if (withRatchet) {
      ref = this.keyRing.registry;
      for (j = 0, len = ref.length; j < len; j++) {
        guest = ref[j];
        this._loadRatchets(guest);
        this.krLocal.selfDestruct(withRatchet);
        this.krGuest.selfDestruct(withRatchet);
      }
    }
    return RatchetBox.__super__.selfDestruct.call(this, overseerAuthorized);
  };

  return RatchetBox;

})(Mailbox);

module.exports = RatchetBox;

if (window.__CRYPTO_DEBUG) {
  window.RatchetBox = RatchetBox;
}


},{"keyratchet":3,"keyring":4,"keys":5,"mailbox":6,"nacl":9,"utils":13}],11:[function(require,module,exports){
var Config, Keys, Nacl, Relay, Utils,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

Config = require('config');

Keys = require('keys');

Nacl = require('nacl');

Utils = require('utils');

Relay = (function() {
  function Relay(url) {
    this.url = url != null ? url : null;
    this._ajax = bind(this._ajax, this);
    this._resetState();
    this.lastError = null;
    this.RELAY_COMMANDS = ['count', 'upload', 'download', 'delete'];
  }

  Relay.prototype.openConnection = function() {
    return this.getServerToken().then((function(_this) {
      return function() {
        return _this.getServerKey();
      };
    })(this));
  };

  Relay.prototype.getServerToken = function() {
    if (!this.url) {
      throw new Error('getServerToken - no url');
    }
    this.lastError = null;
    if (!this.clientToken) {
      this.clientToken = Nacl.random(Config.RELAY_TOKEN_LEN);
    }
    if (this.clientToken && this.clientToken.length !== Config.RELAY_TOKEN_LEN) {
      throw new Error("Token must be " + Config.RELAY_TOKEN_LEN + " bytes");
    }
    return this._ajax('start_session', this.clientToken.toBase64()).then((function(_this) {
      return function(data) {
        var lines;
        lines = _this._processData(data);
        _this.relayToken = lines[0].fromBase64();
        _this.diff = lines.length === 2 ? parseInt(lines[1]) : 0;
        _this._scheduleExpireSession(Config.RELAY_TOKEN_TIMEOUT);
        if (_this.diff > 4) {
          console.log("Relay " + _this.url + " requested difficulty " + _this.diff + ". Session handshake may take longer.");
        }
        if (_this.diff > 16) {
          return console.log("Attempting handshake at difficulty " + _this.diff + "! This may take a while");
        }
      };
    })(this));
  };

  Relay.prototype.getServerKey = function() {
    var handshake, nonce, sessionHandshake;
    if (!(this.url && this.clientToken && this.relayToken)) {
      throw new Error('getServerKey - missing params');
    }
    this.lastError = null;
    this.h2ClientToken = Nacl.h2(this.clientToken).toBase64();
    handshake = this.clientToken.concat(this.relayToken);
    if (this.diff === 0) {
      sessionHandshake = Nacl.h2(handshake).toBase64();
    } else {
      nonce = Nacl.random(32);
      while (!Utils.arrayZeroBits(Nacl.h2(handshake.concat(nonce)), this.diff)) {
        nonce = Nacl.random(32);
      }
      sessionHandshake = nonce.toBase64();
    }
    return this._ajax('verify_session', this.h2ClientToken + "\r\n" + sessionHandshake + "\r\n").then((function(_this) {
      return function(d) {
        var relayPk;
        relayPk = d.fromBase64();
        _this.relayKey = new Keys({
          boxPk: relayPk
        });
        return _this.online = true;
      };
    })(this));
  };

  Relay.prototype.connectMailbox = function(mbx) {
    var clientTemp, h2Sign, inner, maskedClientTempPk, outer, relayId, sign;
    if (!((mbx != null) && this.online && (this.relayKey != null) && (this.url != null))) {
      throw new Error('connectMailbox - missing params');
    }
    this.lastError = null;
    relayId = "relay_" + this.url;
    clientTemp = mbx.createSessionKey(relayId).boxPk;
    mbx.keyRing.addTempGuest(relayId, this.relayKey.strPubKey());
    delete this.relayKey;
    maskedClientTempPk = clientTemp.toBase64();
    sign = clientTemp.concat(this.relayToken).concat(this.clientToken);
    h2Sign = Nacl.h2(sign);
    inner = mbx.encodeMessage(relayId, h2Sign);
    inner['pub_key'] = mbx.keyRing.getPubCommKey();
    outer = mbx.encodeMessage("relay_" + this.url, inner, true);
    return this._ajax('prove', (this.h2ClientToken + "\r\n") + (maskedClientTempPk + "\r\n") + (outer.nonce + "\r\n") + ("" + outer.ctext)).then((function(_this) {
      return function(d) {};
    })(this));
  };

  Relay.prototype.runCmd = function(cmd, mbx, params) {
    var data, message;
    if (params == null) {
      params = null;
    }
    if (!((cmd != null) && (mbx != null))) {
      throw new Error('runCmd - missing params');
    }
    if (indexOf.call(this.RELAY_COMMANDS, cmd) < 0) {
      throw new Error("Relay " + this.url + " doesn't support " + cmd);
    }
    data = {
      cmd: cmd
    };
    if (params) {
      data = Utils.extend(data, params);
    }
    message = mbx.encodeMessage("relay_" + this.url, data, true);
    return this._ajax('command', ((mbx.hpk().toBase64()) + "\r\n") + (message.nonce + "\r\n") + ("" + message.ctext)).then((function(_this) {
      return function(d) {
        if (cmd === 'upload') {
          return;
        }
        if (d == null) {
          throw new Error(_this.url + " - " + cmd + " error");
        }
        if (cmd === 'count' || cmd === 'download') {
          return _this.result = _this._processResponse(d, mbx, cmd);
        } else {
          return _this.result = JSON.parse(d);
        }
      };
    })(this));
  };

  Relay.prototype._processResponse = function(d, mbx, cmd) {
    var ctext, datain, nonce;
    datain = this._processData(d);
    if (datain.length !== 2) {
      throw new Error(this.url + " - " + cmd + ": Bad response");
    }
    nonce = datain[0];
    ctext = datain[1];
    return mbx.decodeMessage("relay_" + this.url, nonce, ctext, true);
  };

  Relay.prototype._processData = function(d) {
    var datain;
    datain = d.split('\r\n');
    if (!(datain.length >= 2)) {
      datain = d.split('\n');
    }
    return datain;
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

  Relay.prototype.download = function(mbx) {
    return this.runCmd('download', mbx);
  };

  Relay.prototype["delete"] = function(mbx, nonceList) {
    return this.runCmd('delete', mbx, {
      payload: nonceList
    });
  };

  Relay.prototype._resetState = function() {
    this.clientToken = null;
    this.online = false;
    this.relayToken = null;
    this.relayKey = null;
    return this.clientTokenExpiration = null;
  };

  Relay.prototype._scheduleExpireSession = function(tout) {
    if (this.clientTokenExpiration) {
      clearTimeout(this.clientTokenExpiration);
    }
    return this.clientTokenExpiration = setTimeout((function(_this) {
      return function() {
        return _this._resetState();
      };
    })(this), tout);
  };

  Relay.prototype._ajax = function(cmd, data) {
    return Utils.ajax(this.url + "/" + cmd, data);
  };

  return Relay;

})();

module.exports = Relay;

if (window.__CRYPTO_DEBUG) {
  window.Relay = Relay;
}


},{"config":1,"keys":5,"nacl":9,"utils":13}],12:[function(require,module,exports){
var SimpleTestDriver;

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
    if (!this._state) {
      this._load();
    }
    if (this._state[key]) {
      return this._state[key];
    } else {
      return JSON.parse(localStorage.getItem(this._key_tag(key)));
    }
  };

  SimpleTestDriver.prototype.set = function(key, value) {
    if (!this._state) {
      this._load();
    }
    this._state[key] = value;
    localStorage.setItem(this._key_tag(key), JSON.stringify(value));
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

  SimpleTestDriver.prototype._persist = function() {};

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


},{}],13:[function(require,module,exports){
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

  Utils.map = function(array, func) {
    if (typeof $ !== "undefined" && $ !== null ? $.map : void 0) {
      return typeof $ !== "undefined" && $ !== null ? $.map(array, func) : void 0;
    } else {
      return Array.prototype.map.apply(array, [func]);
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
    if (this.ajaxImpl === null) {
      if (typeof Q !== "undefined" && Q !== null ? Q.xhr : void 0) {
        this.setAjaxImpl(function(url, data) {
          return Q.xhr({
            method: 'POST',
            url: url,
            headers: {
              'Accept': 'text/plain',
              'Content-Type': 'text/plain'
            },
            data: data,
            responseType: 'text',
            timeout: Config.RELAY_AJAX_TIMEOUT,
            disableUploadProgress: true
          }).then(function(response) {
            return response.data;
          });
        });
      } else if ((typeof $ !== "undefined" && $ !== null ? $.ajax : void 0) && (typeof $ !== "undefined" && $ !== null ? $.Deferred : void 0)) {
        console.log('default ajax impl: setting to zepto with promises');
        this.setAjaxImpl(function(url, data) {
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
        throw new Error('ajax implementation not set; use q-xhr or $http');
      }
    }
    return this.ajaxImpl(url, data);
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

  Utils.logStack = function(err) {
    var i, j, len, results, s, sl;
    if (!err) {
      err = new Error('stackLog');
    }
    s = err.stack.replace(/^[^\(]+?[\n$]/gm, '').replace(/^\s+at\s+/gm, '').replace(/^Object.<anonymous>\s*\(/gm, '{anonymous}()@').split('\n');
    results = [];
    for (i = j = 0, len = s.length; j < len; i = ++j) {
      sl = s[i];
      results.push(console.log(i + ": " + sl));
    }
    return results;
  };

  return Utils;

})();

module.exports = Utils;

if (window.__CRYPTO_DEBUG) {
  window.Utils = Utils;
}


},{"config":1}]},{},[7])


//# sourceMappingURL=theglow.js.map
