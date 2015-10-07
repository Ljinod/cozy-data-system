// Generated by CoffeeScript 1.9.0
var async, db, initializeDSView, log, productionOrTest, randomString, recoverApp, recoverDesignDocs, recoverDocs, request,
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

request = {};

log = require('printit')({
  date: true,
  prefix: 'lib/request'
});

randomString = function(length) {
  var string;
  string = "";
  while (string.length < length) {
    string = string + Math.random().toString(36).substr(2);
  }
  return string.substr(0, length);
};

productionOrTest = process.env.NODE_ENV === "production" || process.env.NODE_ENV === "test";

module.exports.create = (function(_this) {
  return function(app, req, views, newView, callback) {
    var storeRam;
    storeRam = function(path) {
      if (request[app] == null) {
        request[app] = {};
      }
      request[app][req.type + "/" + req.req_name] = path;
      return callback(null, path);
    };
    if (productionOrTest) {
      if (((views != null ? views[req.req_name] : void 0) != null) && JSON.stringify(views[req.req_name]) !== JSON.stringify(newView)) {
        return storeRam(app + "-" + req.req_name);
      } else {
        if ((views != null ? views[app + "-" + req.req_name] : void 0) != null) {
          delete views[app + "-" + req.req_name];
          return db.merge("_design/" + req.type, {
            views: views
          }, function(err, response) {
            if (err) {
              log.error("[Definition] err: " + err.message);
            }
            return storeRam(req.req_name);
          });
        } else {
          return storeRam(req.req_name);
        }
      }
    } else {
      return callback(null, req.req_name);
    }
  };
})(this);

module.exports.get = (function(_this) {
  return function(app, req, callback) {
    var _ref;
    if (productionOrTest && (((_ref = request[app]) != null ? _ref[req.type + "/" + req.req_name] : void 0) != null)) {
      return callback(request[app][req.type + "/" + req.req_name]);
    } else {
      return callback("" + req.req_name);
    }
  };
})(this);

recoverApp = (function(_this) {
  return function(callback) {
    var apps;
    apps = [];
    return db.view('application/all', function(err, res) {
      if (err) {
        return callback(err);
      } else if (!res) {
        return callback(null, []);
      } else {
        res.forEach(function(app) {
          return apps.push(app.name);
        });
        return callback(null, apps);
      }
    });
  };
})(this);

recoverDocs = (function(_this) {
  return function(res, docs, callback) {
    var doc;
    if (res && res.length !== 0) {
      doc = res.pop();
      return db.get(doc.id, function(err, result) {
        docs.push(result);
        return recoverDocs(res, docs, callback);
      });
    } else {
      return callback(null, docs);
    }
  };
})(this);

recoverDesignDocs = (function(_this) {
  return function(callback) {
    var filterRange;
    filterRange = {
      startkey: "_design/",
      endkey: "_design0"
    };
    return db.all(filterRange, function(err, res) {
      if (err != null) {
        return callback(err);
      }
      return recoverDocs(res, [], callback);
    });
  };
})(this);

initializeDSView = function(callback) {
  var views;
  views = {
    doctypes: {
      all: {
        map: "function(doc) {\n    if(doc.docType) {\n        return emit(doc.docType, null);\n    }\n}",
        reduce: "function(key, values) {\n    return true;\n}"
      }
    },
    device: {
      all: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"device\") {\n        return emit(doc._id, doc);\n    }\n}"
      },
      byLogin: {
        map: "function (doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"device\") {\n        return emit(doc.login, doc)\n    }\n}"
      }
    },
    application: {
      all: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"application\") {\n        return emit(doc._id, doc);\n    }\n}"
      },
      byslug: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"application\") {\n        return emit(doc.slug, doc);\n    }\n}"
      }
    },
    withoutDocType: {
      all: {
        map: "function(doc) {\n    if (!doc.docType) {\n        return emit(doc._id, doc);\n    }\n}"
      }
    },
    access: {
      all: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"access\") {\n        return emit(doc._id, doc);\n    }\n}"
      },
      byApp: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"access\") {\n        return emit(doc.app, doc);\n    }\n}"
      }
    },
    binary: {
      all: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"binary\") {\n        emit(doc._id, null);\n    }\n}"
      },
      byDoc: {
        map: "function(doc) {\n    if(doc.binary) {\n        for (bin in doc.binary) {\n            emit(doc.binary[bin].id, doc._id);\n        }\n    }\n}"
      }
    },
    file: {
      withoutThumb: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"file\") {\n        if(doc.class === \"image\" && doc.binary && doc.binary.file && !doc.binary.thumb) {\n            emit(doc._id, null);\n        }\n    }\n}"
      }
    },
    tags: {
      all: {
        map: "function (doc) {\nvar _ref;\nreturn (_ref = doc.tags) != null ? typeof _ref.forEach === \"function\" ? _ref.forEach(function(tag) {\n   return emit(tag, null);\n    }) : void 0 : void 0;\n}",
        reduce: "function(key, values) {\n    return true;\n}"
      }
    },
    sharingRule: {
      all: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"sharingrule\") {\n        return emit(doc._id, doc);\n    }\n}"
      }
    },
    sharing: {
      all: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"sharing\") {\n        return emit(doc._id, doc);\n    }\n}"
      }
    },
    usersharing: {
      all: {
        map: "function(doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"usersharing\") {\n        return emit(doc._id, doc);\n    }\n}"
      },
      byLogin: {
        map: "function (doc) {\n    if(doc.docType && doc.docType.toLowerCase() === \"usersharing\") {\n        return emit(doc.login, doc)\n    }\n}"
      }
    }
  };
  return async.forEach(Object.keys(views), function(docType, cb) {
    var view;
    view = views[docType];
    return db.get("_design/" + docType, function(err, doc) {
      var type, _i, _len, _ref;
      if (err && err.error === 'not_found') {
        return db.save("_design/" + docType, view, cb);
      } else if (err) {
        log.error(err);
        return cb();
      } else {
        _ref = Object.keys(view);
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          type = _ref[_i];
          doc.views[type] = view[type];
        }
        return db.save("_design/" + docType, doc, cb);
      }
    });
  }, callback);
};

module.exports.init = (function(_this) {
  return function(callback) {
    var removeEmptyView, storeAppView;
    removeEmptyView = function(doc, callback) {
      if (Object.keys(doc.views).length === 0 || ((doc != null ? doc.views : void 0) == null)) {
        return db.remove(doc._id, doc._rev, function(err, response) {
          if (err) {
            log.error("[Definition] err: " + err.message);
          }
          return callback(err);
        });
      } else {
        return callback();
      }
    };
    storeAppView = function(apps, doc, view, body, callback) {
      var app, req_name, type, _ref;
      if (view.indexOf('-') !== -1) {
        if (_ref = view.split('-')[0], __indexOf.call(apps, _ref) >= 0) {
          app = view.split('-')[0];
          type = doc._id.substr(8, doc._id.length - 1);
          req_name = view.split('-')[1];
          if (!request[app]) {
            request[app] = {};
          }
          request[app][type + "/" + req_name] = view;
          return callback();
        } else {
          delete doc.views[view];
          return db.merge(doc._id, {
            views: doc.views
          }, function(err, response) {
            if (err) {
              log.error("[Definition] err: " + err.message);
            }
            return removeEmptyView(doc, function(err) {
              if (err != null) {
                log.error(err);
              }
              return callback();
            });
          });
        }
      } else {
        return callback();
      }
    };
    return initializeDSView(function() {
      if (productionOrTest) {
        return recoverApp((function(_this) {
          return function(err, apps) {
            if (err != null) {
              return callback(err);
            }
            return recoverDesignDocs(function(err, docs) {
              if (err != null) {
                return callback(err);
              }
              return async.forEach(docs, function(doc, cb) {
                return async.forEach(Object.keys(doc.views), function(view, cb) {
                  var body;
                  body = doc.views[view];
                  return storeAppView(apps, doc, view, body, cb);
                }, function(err) {
                  return removeEmptyView(doc, function(err) {
                    if (err != null) {
                      log.error(err);
                    }
                    return cb();
                  });
                });
              }, function(err) {
                if (err != null) {
                  log.error(err);
                }
                return callback();
              });
            });
          };
        })(this));
      } else {
        return callback(null);
      }
    });
  };
})(this);
