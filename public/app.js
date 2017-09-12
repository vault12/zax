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
      return this.$window.location.origin;
    };

    function CryptoService($window) {
      this.$window = $window;
      this.glow = this.$window.glow;
      this.nacl = this.$window.nacl_factory.instantiate(function() {});
      this.Mailbox = this.glow.MailBox;
      this.Relay = this.glow.Relay;
      this.KeyRing = this.glow.KeyRing;
      this.Keys = this.glow.Keys;
      this.CryptoStorage = this.glow.CryptoStorage;
      this.CryptoStorage.startStorageSystem(new this.glow.SimpleStorageDriver(this.relayUrl()));
      this.glow.Utils.setAjaxImpl(function(url, data) {
        return axios({
          url: url,
          method: 'post',
          headers: {
            'Accept': 'text/plain',
            'Content-Type': 'text/plain'
          },
          data: data,
          responseType: 'text',
          timeout: 2000
        }).then(function(response) {
          return response.data;
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
      return mailbox.connectToRelay(this.relay).then((function(_this) {
        return function() {
          return mailbox.relayCount(_this.relay).then(function(count) {
            mailbox.messageCount = count;
            return count;
          });
        };
      })(this));
    };

    RelayService.prototype.getMessages = function(mailbox) {
      return mailbox.getRelayMessages(this.relay);
    };

    RelayService.prototype.deleteMessages = function(mailbox, noncesToDelete) {
      return mailbox.connectToRelay(this.relay).then((function(_this) {
        return function() {
          return mailbox.relayDelete(noncesToDelete, _this.relay);
        };
      })(this));
    };

    RelayService.prototype.newMailbox = function(mailboxName, options) {
      var next;
      if (options == null) {
        options = {};
      }
      next = null;
      if (options.secret) {
        if (!mailboxName) {
          mailboxName = this._randomString();
        }
        next = this.CryptoService.Mailbox.fromSecKey(options.secret.fromBase64(), mailboxName).then((function(_this) {
          return function(mailbox) {
            console.log("created mailbox " + mailboxName + ":" + options.secret + " from secret");
            return mailbox;
          };
        })(this));
      } else if (options.seed) {
        next = this.CryptoService.Mailbox.fromSeed(options.seed, mailboxName).then((function(_this) {
          return function(mailbox) {
            console.log("created mailbox " + mailboxName + ":" + options.seed + " from seed");
            return mailbox;
          };
        })(this));
      } else {
        next = this.CryptoService.Mailbox["new"](mailboxName).then((function(_this) {
          return function(mailbox) {
            console.log("created mailbox " + mailboxName + " from scratch");
            return mailbox;
          };
        })(this));
      }
      return next.then((function(_this) {
        return function(mailbox) {
          return _this.messageCount(mailbox).then(function() {
            var fn, mbx, name, ref, tasks;
            tasks = [];
            ref = _this.mailboxes;
            fn = function(name, mbx) {
              return tasks.push(mbx.keyRing.addGuest(mailbox.identity, mailbox.getPubCommKey()).then(function() {
                return mailbox.keyRing.addGuest(mbx.identity, mbx.getPubCommKey());
              }));
            };
            for (name in ref) {
              mbx = ref[name];
              fn(name, mbx);
            }
            return _this.$q.all(tasks).then(function() {
              _this.mailboxes[mailbox.identity] = mailbox;
              return mailbox;
            });
          });
        };
      })(this));
    };

    RelayService.prototype.destroyMailbox = function(mailbox) {
      var mbx, name, ref, tasks;
      tasks = [];
      ref = this.mailboxes;
      for (name in ref) {
        mbx = ref[name];
        if (mailbox.keyRing.storage.root === mbx.keyRing.storage.root) {
          ((function(_this) {
            return function(mailbox, name) {
              return tasks.push(mailbox.selfDestruct(true).then(function() {
                console.log('deleting ' + name);
                return delete _this.mailboxes[name];
              }));
            };
          })(this))(mailbox, name);
        }
      }
      return this.$q.all(tasks);
    };

    RelayService.prototype.sendToVia = function(recipient, mailbox, message) {
      return mailbox.sendToVia(recipient, this.relay, message);
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

    function RequestPaneController(RelayService, $scope, $q) {
      var first_names, i, j, k, key, l, len, len1, name, next, ref;
      $('#key-confirmation').hide();
      $('#send-confirmation').hide();
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
        return RelayService.messageCount(mailbox).then(function() {
          return $scope.$apply();
        });
      };
      $scope.getMessages = function(mailbox) {
        return RelayService.getMessages(mailbox).then(function(data) {
          var l, len1, msg;
          if (!mailbox.messages) {
            mailbox.messages = [];
            mailbox.messagesNonces = [];
          }
          for (l = 0, len1 = data.length; l < len1; l++) {
            msg = data[l];
            if (mailbox.messagesNonces.indexOf(msg.nonce) === -1) {
              console.log("incoming message:", msg);
              mailbox.messagesNonces.push(msg.nonce);
              mailbox.messages.push(msg);
            }
          }
          return $scope.$apply();
        });
      };
      $scope.deleteMessages = function(mailbox, messagesToDelete) {
        var noncesToDelete;
        if (messagesToDelete == null) {
          messagesToDelete = null;
        }
        noncesToDelete = messagesToDelete || mailbox.messagesNonces || [];
        return RelayService.deleteMessages(mailbox, noncesToDelete).then(function() {
          var index, l, len1, msg;
          if (noncesToDelete.length === 0) {
            mailbox.messages = [];
            mailbox.messagesNonces = [];
          } else {
            for (l = 0, len1 = noncesToDelete.length; l < len1; l++) {
              msg = noncesToDelete[l];
              index = mailbox.messagesNonces.indexOf(msg);
              mailbox.messagesNonces.splice(index, 1);
              mailbox.messages.splice(index, 1);
            }
          }
          return $scope.$apply();
        });
      };
      $scope.sendMessage = (function(_this) {
        return function(mailbox, outgoing) {
          return RelayService.sendToVia(outgoing.recipient, mailbox, outgoing.message).then(function(data) {
            $('#send-confirmation').show().fadeOut(3000);
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
          return RelayService.destroyMailbox(mailbox).then(function() {
            return localStorage.removeItem(_this.mailboxPrefix + "." + name);
          });
        };
      })(this);
      $scope.selectMailbox = function(mailbox) {
        return $scope.activeMailbox = mailbox;
      };
      $scope.addMailbox = (function(_this) {
        return function(name, options) {
          return RelayService.newMailbox(name, options).then(function(mailbox) {
            localStorage.setItem(_this.mailboxPrefix + "." + name, mailbox.identity);
            return $scope.newMailbox = mailbox;
          });
        };
      })(this);
      $scope.addMailboxes = (function(_this) {
        return function(quantityToAdd) {
          var l, results;
          return (function() {
            results = [];
            for (var l = 1; 1 <= quantityToAdd ? l <= quantityToAdd : l >= quantityToAdd; 1 <= quantityToAdd ? l++ : l--){ results.push(l); }
            return results;
          }).apply(this).reduce((function(prev, i) {
            return prev.then(function() {
              return $scope.addMailbox(_this.names.shift());
            });
          }), $q.all());
        };
      })(this);
      $scope.addPublicKey = (function(_this) {
        return function(mailbox, key) {
          if (mailbox.keyRing.addGuest(key.name, key.key)) {
            $('#key-confirmation').show().fadeOut(3000);
            return $scope.pubKey = {
              name: "",
              key: ""
            };
          }
        };
      })(this);
      next = $q.all();
      ref = Object.keys(localStorage);
      for (l = 0, len1 = ref.length; l < len1; l++) {
        key = ref[l];
        if (key.indexOf(this.mailboxPrefix) === 0) {
          (function(key) {
            return next = next.then(function() {
              return $scope.addMailbox(localStorage.getItem(key));
            });
          })(key);
        }
      }
      next;
    }

    return RequestPaneController;

  })();

  angular.module('app').controller('RequestPaneController', ['RelayService', '$scope', '$q', RequestPaneController]);

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
