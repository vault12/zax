(function() {
  angular.module('app', []);

  angular.module('app').filter('isEmpty', function() {
    return function(obj) {
      var key;
      for (key in obj) {
        if (obj.hasOwnProperty(key)) {
          return false;
        }
      }
      return true;
    };
  });

}).call(this);

(function() {
  var CryptoService;

  CryptoService = (function() {
    CryptoService.prototype.relayUrl = function() {
      var org, test;
      org = this.$window.location.origin;
      test = 'https://zax_test.vault12.com';
      if (org.includes('localhost')) {
        return test;
      } else {
        return org;
      }
    };

    function CryptoService($window) {
      this.$window = $window;
      this.glow = this.$window.glow;
      this.nacl = this.$window.nacl_factory.instantiate();
      this.Mailbox = this.glow.MailBox;
      this.Relay = this.glow.Relay;
      this.KeyRing = this.glow.KeyRing;
      this.Keys = this.glow.Keys;
      this.CryptoStorage = this.glow.CryptoStorage;
      this.CryptoStorage.startStorageSystem(new this.glow.SimpleStorageDriver(this.relayUrl()));
      this.glow.Utils.setAjaxImpl(function(url, data) {
        return $.ajax({
          method: 'POST',
          url: url,
          headers: {
            'Accept': 'text/plain',
            'Content-Type': 'text/plain'
          },
          data: data,
          responseType: 'text',
          timeout: 2000
        }).then(function(response) {
          return response;
        });
      });
    }

    return CryptoService;

  })();

  angular.module('app').service('CryptoService', ['$window', CryptoService]);

}).call(this);

(function() {
  var RelayService,
    bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    slice = [].slice;

  RelayService = (function() {
    RelayService.prototype.host = "";

    RelayService.prototype.headers = {
      "Content-Type": "text/plain"
    };

    RelayService.prototype.mailboxes = {};

    function RelayService($http, $q, CryptoService, $location) {
      this.$http = $http;
      this.$q = $q;
      this.CryptoService = CryptoService;
      this.newMailbox = bind(this.newMailbox, this);
      this.host = this.CryptoService.relayUrl();
      this._newRelay();
    }

    RelayService.prototype.messageCount = function(mailbox) {
      return this._defer((function(_this) {
        return function() {
          return mailbox.connectToRelay(_this.relay);
        };
      })(this)).then((function(_this) {
        return function() {
          return _this._defer(function() {
            return mailbox.relay_count();
          });
        };
      })(this));
    };

    RelayService.prototype.getMessages = function(mailbox) {
      return this._defer((function(_this) {
        return function() {
          return mailbox.getRelayMessages(_this.relay);
        };
      })(this));
    };

    RelayService.prototype.deleteMessages = function(mailbox, messagesToDelete) {
      if (messagesToDelete == null) {
        messagesToDelete = null;
      }
      if (!messagesToDelete) {
        messagesToDelete = mailbox.relay_nonce_list();
      }
      return this._defer((function(_this) {
        return function() {
          return mailbox.connectToRelay(_this.relay);
        };
      })(this)).then((function(_this) {
        return function() {
          return _this._defer(function() {
            return mailbox.relay_delete(messagesToDelete);
          });
        };
      })(this));
    };

    RelayService.prototype.newMailbox = function(mailboxName, options) {
      var mailbox, mbx, name, ref;
      if (mailboxName == null) {
        mailboxName = "";
      }
      if (options == null) {
        options = {};
      }
      if (options.secret) {
        mailbox = new this.CryptoService.Mailbox.fromSecKey(options.secret.fromBase64(), mailboxName);
        console.log("created mailbox " + mailboxName + ":" + options.secret + " from secret");
      } else if (options.seed) {
        mailbox = new this.CryptoService.Mailbox.fromSeed(options.seed, mailboxName);
        console.log("created mailbox " + mailboxName + ":" + options.seed + " from seed");
      } else {
        mailbox = new this.CryptoService.Mailbox(mailboxName);
        console.log("created mailbox " + mailboxName + " from scratch");
      }
      ref = this.mailboxes;
      for (name in ref) {
        mbx = ref[name];
        mbx.keyRing.addGuest(mailbox.identity, mailbox.getPubCommKey());
        mailbox.keyRing.addGuest(mbx.identity, mbx.getPubCommKey());
      }
      if (mailbox.identity) {
        return this.mailboxes[mailbox.identity] = mailbox;
      }
    };

    RelayService.prototype.destroyMailbox = function(mailbox) {
      var mbx, name, ref, results;
      ref = this.mailboxes;
      results = [];
      for (name in ref) {
        mbx = ref[name];
        if (mailbox.keyRing.storage.root === mbx.keyRing.storage.root) {
          mailbox.selfDestruct(true);
          results.push(delete this.mailboxes[name]);
        } else {
          results.push(void 0);
        }
      }
      return results;
    };

    RelayService.prototype.sendToVia = function(recipient, mailbox, message) {
      var deffered;
      deffered = this.$q.defer();
      deffered.resolve(mailbox.sendToVia(recipient, this.relay, message));
      return deffered.promise;
    };

    RelayService.prototype._defer = function(fnToDefer) {
      var deffered;
      deffered = this.$q.defer();
      deffered.resolve(fnToDefer());
      return deffered.promise;
    };

    RelayService.prototype._newRelay = function() {
      return this.relay = new this.CryptoService.Relay(this.host);
    };

    RelayService.prototype._concat = function() {
      var array, arrays, concatArray, i, item, j, len, len1;
      arrays = 1 <= arguments.length ? slice.call(arguments, 0) : [];
      concatArray = [];
      for (i = 0, len = arrays.length; i < len; i++) {
        array = arrays[i];
        for (j = 0, len1 = array.length; j < len1; j++) {
          item = array[j];
          concatArray.push(item);
        }
      }
      return concatArray;
    };

    RelayService.prototype._randomString = function(length) {
      var id;
      if (length == null) {
        length = 32;
      }
      id = "";
      while (id.length < length) {
        id += Math.random().toString(36).substr(2);
      }
      return id.substr(0, length);
    };

    return RelayService;

  })();

  angular.module('app').service('RelayService', ['$http', '$q', 'CryptoService', '$location', RelayService]);

}).call(this);

(function() {
  var RequestPaneController;

  RequestPaneController = (function() {
    RequestPaneController.prototype.mailboxPrefix = "_mailbox";

    function RequestPaneController(RelayService, $scope) {
      var first_names, i, j, k, key, l, len, len1, name, ref;
      first_names = ["Alice", "Bob", "Charlie", "Chuck", "Dave", "Erin", "Eve", "Faith", "Frank", "Mallory", "Oscar", "Peggy", "Pat", "Sam", "Sally", "Sybil", "Trent", "Trudy", "Victor", "Walter", "Wendy"].sort(function() {
        return .5 - Math.random();
      });
      this.names = [];
      for (i = j = 1; j <= 20; i = ++j) {
        for (k = 0, len = first_names.length; k < len; k++) {
          name = first_names[k];
          if (i === 1) {
            this.names.push("" + name);
          } else {
            this.names.push(name + " " + i);
          }
        }
      }
      $scope.mailboxes = RelayService.mailboxes;
      $scope.relay = RelayService.relay;
      $scope.activeMailbox = null;
      $scope.mailbox = {};
      $scope.addMailboxVisible = true;
      $scope.quantity = 3;
      $scope.messageCount = function(mailbox) {
        return RelayService.messageCount(mailbox).then(function(data) {
          return mailbox.messageCount = "" + $scope.relay.result;
        });
      };
      $scope.getMessages = function(mailbox) {
        return RelayService.getMessages(mailbox).then(function(data) {
          var l, len1, msg, ref, results;
          if (!mailbox.messages) {
            mailbox.messages = [];
            mailbox.messagesNonces = [];
          }
          ref = mailbox.lastDownload;
          results = [];
          for (l = 0, len1 = ref.length; l < len1; l++) {
            msg = ref[l];
            if (mailbox.messagesNonces.indexOf(msg.nonce) === -1) {
              console.log("incoming message:", msg);
              mailbox.messagesNonces.push(msg.nonce);
              results.push(mailbox.messages.push(msg));
            } else {
              results.push(void 0);
            }
          }
          return results;
        });
      };
      $scope.deleteMessages = function(mailbox, messagesToDelete) {
        if (messagesToDelete == null) {
          messagesToDelete = [];
        }
        return RelayService.deleteMessages(mailbox, messagesToDelete).then(function() {
          var index, l, len1, msg, results;
          if (messagesToDelete.length === 0) {
            mailbox.messages = [];
            return mailbox.messagesNonces = [];
          } else {
            results = [];
            for (l = 0, len1 = messagesToDelete.length; l < len1; l++) {
              msg = messagesToDelete[l];
              index = mailbox.messagesNonces.indexOf(msg);
              mailbox.messagesNonces.splice(index, 1);
              results.push(mailbox.messages.splice(index, 1));
            }
            return results;
          }
        });
      };
      $scope.sendMessage = (function(_this) {
        return function(mailbox, outgoing) {
          return RelayService.sendToVia(outgoing.recipient, mailbox, outgoing.message).then(function(data) {
            return $scope.outgoing = {
              message: "",
              recipient: ""
            };
          });
        };
      })(this);
      $scope.deleteMailbox = (function(_this) {
        return function(mailbox) {
          name = mailbox.identity;
          RelayService.destroyMailbox(mailbox);
          return localStorage.removeItem(_this.mailboxPrefix + "." + name);
        };
      })(this);
      $scope.selectMailbox = function(mailbox) {
        return $scope.activeMailbox = mailbox;
      };
      $scope.addMailbox = (function(_this) {
        return function(name, options) {
          if (localStorage.setItem(_this.mailboxPrefix + "." + name, RelayService.newMailbox(name, options).identity)) {
            return $scope.newMailbox = {
              name: "",
              options: null
            };
          }
        };
      })(this);
      $scope.addMailboxes = (function(_this) {
        return function(quantityToAdd) {
          var l, ref;
          for (i = l = 1, ref = quantityToAdd; 1 <= ref ? l <= ref : l >= ref; i = 1 <= ref ? ++l : --l) {
            $scope.addMailbox(_this.names[1]);
            _this.names.splice(0, 1);
          }
          return quantityToAdd = 0;
        };
      })(this);
      $scope.addPublicKey = (function(_this) {
        return function(mailbox, key) {
          if (mailbox.keyRing.addGuest(key.name, key.key)) {
            return $scope.pubKey = {
              name: "",
              key: ""
            };
          }
        };
      })(this);
      ref = Object.keys(localStorage);
      for (l = 0, len1 = ref.length; l < len1; l++) {
        key = ref[l];
        if (key.indexOf(this.mailboxPrefix) === 0) {
          $scope.addMailbox(localStorage.getItem(key));
        }
      }
    }

    return RequestPaneController;

  })();

  angular.module('app').controller('RequestPaneController', ["RelayService", "$scope", RequestPaneController]);

}).call(this);

(function() {
  var requestPane;

  requestPane = function(RequestService, LoggerService, base64) {
    var directive;
    directive = {
      transclude: true,
      restrict: 'E',
      templateUrl: "request-pane/request-pane.template.html",
      controller: "RequestPaneController",
      scope: "=",
      link: function(scope, attrs, element) {}
    };
    return directive;
  };

  angular.module('app').directive("requestPane", [requestPane]);

}).call(this);

//# sourceMappingURL=app.js.map
