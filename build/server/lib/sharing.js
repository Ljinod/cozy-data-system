// Generated by CoffeeScript 1.9.0
var async, binaryHandling, bufferIds, cancelReplication, convertTuples, db, deleteResults, getActiveTasks, getCozyAddressFromUserID, getRepID, getRuleById, getbinariesIds, insertResults, mapDoc, mapDocInRules, matchAfterInsert, matching, notifyTarget, plug, removeDuplicates, removeNullValues, removeReplication, replicateDocs, request, rules, saveReplication, saveRule, selectInPlug, shareDocs, shareIDInArray, sharingProcess, startShares, updateActiveRep, updateProcess, updateResults, userInArray, userSharing;

plug = require('./plug');

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

request = require('request-json');

rules = [];

bufferIds = [];

module.exports.evalInsert = function(doc, id, callback) {
  console.log('doc insert : ' + JSON.stringify(doc));
  return mapDocInRules(doc, id, function(err, mapResults) {
    if (err != null) {
      return callback(err);
    }
    return async.eachSeries(mapResults, insertResults, function(err) {
      if (err != null) {
        return callback(err);
      }
      console.log('mapping results insert : ' + JSON.stringify(mapResults));
      return matchAfterInsert(mapResults, function(err, acls) {
        if (err != null) {
          return callback(err);
        }
        if (!((acls != null) && acls.length > 0)) {
          return callback(null);
        }
        return startShares(acls, function(err) {
          return callback(err);
        });
      });
    });
  });
};

module.exports.evalUpdate = function(id, isBinaryUpdate, callback) {
  return db.get(id, function(err, doc) {
    console.log('doc update : ' + JSON.stringify(doc));
    return mapDocInRules(doc, id, function(err, mapResults) {
      if (err != null) {
        return callback(err);
      }
      console.log('mapping results update : ' + JSON.stringify(mapResults));
      return selectInPlug(id, function(err, selectResults) {
        if (err != null) {
          return callback(err);
        }
        return updateProcess(id, mapResults, selectResults, isBinaryUpdate, function(err, res) {
          return callback(err, res);
        });
      });
    });
  });
};

insertResults = function(mapResult, callback) {
  console.log('go insert docs');
  return async.series([
    function(_callback) {
      var doc, ids;
      if ((mapResult != null ? mapResult.doc : void 0) == null) {
        return _callback(null);
      }
      doc = mapResult.doc;
      ids = doc.binaries != null ? doc.binaries : [doc.docID];
      return plug.insertDocs(ids, doc.shareID, doc.userDesc, function(err) {
        if (err == null) {
          console.log("docs " + JSON.stringify(ids + " inserted in PlugDB"));
        }
        if (err != null) {
          return _callback(err);
        } else {
          return _callback(null);
        }
      });
    }, function(_callback) {
      var ids, user;
      if ((mapResult != null ? mapResult.user : void 0) == null) {
        return _callback(null);
      }
      user = mapResult.user;
      ids = user.binaries != null ? user.binaries : [user.userID];
      return plug.insertUsers(ids, user.shareID, user.userDesc, function(err) {
        if (err == null) {
          console.log("users " + JSON.stringify(ids + " inserted in PlugDB"));
        }
        if (err != null) {
          return _callback(err);
        } else {
          return _callback(null);
        }
      });
    }
  ], function(err) {
    return callback(err);
  });
};

updateResults = function(mapResult, callback) {
  return async.series([
    function(_callback) {
      if (mapResult.docID != null) {
        return plug.insertDoc(mapResult.docID, mapResult.shareID, mapResult.userDesc, function(err) {
          if (err == null) {
            console.log("doc " + mapResult.docID + " inserted in PlugDB");
          }
          if (err != null) {
            return _callback(err);
          } else {
            return _callback(null);
          }
        });
      } else {
        return _callback(null);
      }
    }, function(_callback) {
      if (mapResult.userID != null) {
        return plug.insertUser(mapResult.userID, mapResult.shareID, mapResult.userDesc, function(err) {
          if (err == null) {
            console.log("user " + mapResult.userID + " inserted in PlugDB");
          }
          if (err != null) {
            return _callback(err);
          } else {
            return _callback(null);
          }
        });
      } else {
        return _callback(null);
      }
    }
  ], function(err) {
    return callback(err);
  });
};

deleteResults = function(select, callback) {
  return async.series([
    function(_callback) {
      var doc;
      if (select.doc == null) {
        return _callback(null);
      }
      doc = select.doc;
      return plug.deleteMatch(plug.USERS, doc.idPlug, doc.shareID, function(err, res) {
        if (err != null) {
          return _callback(err);
        }
        if (res == null) {
          return _callback(null);
        }
        return plug.deleteDoc(doc.idPlug, function(err) {
          return _callback(err, res);
        });
      });
    }, function(_callback) {
      var user;
      if (select.user == null) {
        return _callback(null);
      }
      user = select.user;
      return plug.deleteMatch(plug.DOCS, user.idPlug, user.shareID, function(err, res) {
        if (err != null) {
          return _callback(err);
        }
        if (res == null) {
          return _callback(null);
        }
        return plug.deleteDoc(user.idPlug, function(err) {
          return _callback(err, res);
        });
      });
    }
  ], function(err, results) {
    var acls;
    if (results != null) {
      console.log('delete results : ' + JSON.stringify(results));
    }
    acls = {
      doc: results[0],
      user: results[1]
    };
    return callback(err, acls);
  });
};

selectInPlug = function(id, callback) {
  return async.series([
    function(_callback) {
      return plug.selectDocsByDocID(id, function(err, res) {
        if (err != null) {
          return _callback(err);
        }
        return _callback(null, res);
      });
    }, function(_callback) {
      return plug.selectUsersByUserID(id, function(err, res) {
        if (err != null) {
          return _callback(err);
        }
        return _callback(null, res);
      });
    }
  ], function(err, results) {
    var res;
    res = {
      doc: results[0],
      user: results[1]
    };
    return callback(err, res);
  });
};

updateProcess = function(id, mapResults, selectResults, isBinaryUpdate, callback) {
  var evalUpdate, existDocOrUser;
  existDocOrUser = function(shareID) {
    var doc, user, _ref, _ref1;
    if (((_ref = selectResults.doc) != null ? _ref.shareID : void 0) != null) {
      if (selectResults.doc.shareID === shareID) {
        doc = selectResults.doc;
      }
    }
    if (((_ref1 = selectResults.user) != null ? _ref1.shareID : void 0) != null) {
      if (selectResults.user.shareID === shareID) {
        user = selectResults.user;
      }
    }
    return {
      doc: doc,
      user: user
    };
  };
  evalUpdate = function(rule, _callback) {
    var mapRes, selectResult;
    mapRes = shareIDInArray(mapResults, rule.id);
    selectResult = existDocOrUser(rule.id);
    console.log('map res : ' + JSON.stringify(mapRes));
    if (mapRes != null) {
      if ((selectResult.doc != null) || (selectResult.user != null)) {
        console.log('map and select ok for ' + rule.id);
        if (isBinaryUpdate) {
          binaryHandling(mapRes, function(err) {
            return _callback(err);
          });
        } else {
          _callback(null);
        }
      } else {
        console.log('map ok for ' + rule.id);
        insertResults(mapRes, function(err) {
          if (err != null) {
            return _callback(err);
          }
          return matching(mapRes, function(err, acls) {
            if (err != null) {
              return _callback(err);
            }
            if (acls == null) {
              return _callback(null);
            }
            return startShares([acls], function(err) {
              return _callback(err);
            });
          });
        });
      }
    } else {
      if ((selectResult.doc != null) || (selectResult.user != null)) {
        console.log('select ok for ' + rule.id);
        deleteResults(selectResult, function(err, acls) {
          if (err != null) {
            return _callback(err);
          }
          if (acls == null) {
            return _callback(null);
          }
          return startShares(acls, function(err) {
            return _callback(err);
          });
        });
      } else {
        _callback(null);
      }
    }
    return _callback();
  };
  return async.eachSeries(rules, evalUpdate, function(err) {
    return callback(err);
  });
};

mapDocInRules = function(doc, id, callback) {
  var evalRule;
  evalRule = function(rule, _callback) {
    var filterDoc, filterUser, mapResult, saveResult;
    mapResult = {};
    saveResult = function(id, shareID, userParams, binaries, isDoc) {
      var res;
      res = {};
      if (isDoc) {
        res.docID = id;
      } else {
        res.userID = id;
      }
      res.shareID = shareID;
      res.userParams = userParams;
      res.binaries = binaries;
      if (isDoc) {
        return mapResult.doc = res;
      } else {
        return mapResult.user = res;
      }
    };
    filterDoc = rule.filterDoc;
    filterUser = rule.filterUser;
    return mapDoc(doc, id, rule.id, filterDoc, function(isDocMaped) {
      var binIds;
      if (isDocMaped) {
        console.log('doc maped !! ');
        binIds = getbinariesIds(doc);
        saveResult(id, rule.id, filterDoc.userParam, binIds, true);
      }
      return mapDoc(doc, id, rule.id, filterUser, function(isUserMaped) {
        if (isUserMaped) {
          console.log('user maped !! ');
          binIds = getbinariesIds(doc);
          saveResult(id, rule.id, filterUser.userParam, binIds, false);
        }
        if ((mapResult.doc == null) && (mapResult.user == null)) {
          return _callback(null, null);
        } else {
          return _callback(null, mapResult);
        }
      });
    });
  };
  return async.map(rules, evalRule, function(err, mapResults) {
    mapResults = Array.prototype.slice.call(mapResults);
    removeNullValues(mapResults);
    return callback(err, mapResults);
  });
};

mapDoc = function(doc, docID, shareID, filter, callback) {
  var ret;
  if (eval(filter.rule)) {
    if (filter.userDesc) {
      ret = eval(filer.userDesc);
    } else {
      ret = true;
    }
    return callback(ret);
  } else {
    return callback(false);
  }
};

matchAfterInsert = function(mapResults, callback) {
  if ((mapResults != null) && mapResults.length > 0) {
    return async.mapSeries(mapResults, matching, function(err, acls) {
      return callback(err, acls);
    });
  } else {
    return callback(null);
  }
};

matching = function(mapResult, callback) {
  return async.series([
    function(_callback) {
      var doc, ids, matchType;
      if (mapResult.doc == null) {
        return _callback(null);
      }
      doc = mapResult.doc;
      matchType = plug.USERS;
      ids = doc.binaries != null ? doc.binaries : [doc.docID];
      return plug.matchAll(matchType, ids, doc.shareID, function(err, acl) {
        return _callback(err, acl);
      });
    }, function(_callback) {
      var ids, matchType, user;
      if (mapResult.user == null) {
        return _callback(null);
      }
      user = mapResult.user;
      matchType = plug.DOCS;
      ids = user.binaries != null ? user.binaries : [user.userID];
      return plug.matchAll(matchType, ids, user.shareID, function(err, acl) {
        return _callback(err, acl);
      });
    }
  ], function(err, results) {
    var acls;
    acls = {
      doc: results[0],
      user: results[1]
    };
    return callback(err, acls);
  });
};

startShares = function(acls, callback) {
  if (!((acls != null) && acls.length > 0)) {
    return callback(null);
  }
  return async.each(acls, function(acl, _callback) {
    return async.parallel([
      function(_cb) {
        if (acl.doc == null) {
          return _cb(null);
        }
        return sharingProcess(acl.doc, function(err) {
          return _cb(err);
        });
      }, function(_cb) {
        if (acl.user == null) {
          return _cb(null);
        }
        return sharingProcess(acl.user, function(err) {
          return _cb(err);
        });
      }
    ], function(err) {
      return _callback(err);
    });
  }, function(err) {
    return callback(err);
  });
};

sharingProcess = function(share, callback) {
  if (!((share != null) && (share.users != null))) {
    return callback(null);
  }
  return async.each(share.users, function(user, _callback) {
    return getCozyAddressFromUserID(user.userID, function(err, url) {
      user.target = url;
      return userSharing(share.shareID, user, share.docIDs, function(err) {
        return _callback(err);
      });
    });
  }, function(err) {
    return callback(err);
  });
};

userSharing = function(shareID, user, ids, callback) {
  var replicationID, rule;
  console.log('share with user : ' + JSON.stringify(user));
  rule = getRuleById(shareID);
  if (rule == null) {
    return callback(null);
  }
  replicationID = getRepID(rule.activeReplications, user.userID);
  console.log('replication id : ' + replicationID);
  if (replicationID != null) {
    return cancelReplication(replicationID, function(err) {
      if (err != null) {
        return callback(err);
      }
      return shareDocs(user, ids, rule, function(err) {
        return callback(err);
      });
    });
  } else {
    bufferIds = ids;
    return notifyTarget(user, rule, function(err) {
      return callback(err);
    });
  }
};

shareDocs = function(user, ids, rule, callback) {
  return replicateDocs(user, ids, function(err, repID) {
    if (err != null) {
      return callback(err);
    }
    return saveReplication(rule, user.userID, repID, function(err) {
      return callback(err, repID);
    });
  });
};

notifyTarget = function(user, rule, callback) {
  var remote, sharing;
  user.target = "http://192.168.50.6:9104";
  sharing = {
    url: 'http://192.168.50.4:9104',
    shareID: rule.id,
    userID: user.userID,
    desc: rule.name
  };
  remote = request.newClient(user.target);
  return remote.post("sharing/request", {
    request: sharing
  }, function(err, res, body) {
    var error;
    console.log('body : ' + JSON.stringify(body));
    if ((err != null) && Object.keys(err).length > 0) {
      error = err;
    }
    return callback(error);
  });
};

module.exports.targetAnswer = function(req, res, next) {
  var answer, rule, user;
  console.log('answer : ' + JSON.stringify(req.body.answer));
  answer = req.body.answer;
  if (answer.accepted === true) {
    console.log('target is ok for sharing, lets go');
    rule = getRuleById(answer.shareID);
    user = {
      login: answer.userID,
      url: "http://192.168.50.6:9104",
      password: answer.password
    };
    return shareDocs(user, bufferIds, rule, function(err, repID) {
      if (err != null) {
        return next(err);
      }
      if (repID == null) {
        res.send(500);
      }
      return res.send(200, repID);
    });
  } else {
    bufferIds = [];
    return console.log('target is not ok for sharing, drop it');
  }
};

module.exports.createNewShare = function(req, res, next) {
  console.log('new share : ' + JSON.stringify(req.body.share));
  return res.send(200);
};

replicateDocs = function(target, ids, callback) {
  var couchTarget, repSourceToTarget, repTargetToSource, sourceURL;
  console.log('lets replicate ' + JSON.stringify(ids + ' on target ' + target.url));
  console.log('user : ' + target.user + ' - pwd : ' + target.password);
  sourceURL = "http://192.168.50.4:5984/cozy";
  couchTarget = request.newClient(target.url);
  couchTarget.setBasicAuth(target.login, target.password);
  repSourceToTarget = {
    source: sourceURL,
    target: target.url,
    continuous: true,
    doc_ids: ids
  };
  repTargetToSource = {
    source: "cozy",
    target: sourceURL,
    continuous: true,
    doc_ids: ids
  };
  return couchTarget.post("replication/", repSourceToTarget, function(err, res, body) {
    var replicationID;
    if (err != null) {
      return callback(err);
    } else if (!body.ok) {
      console.log(JSON.stringify(body));
      return callback(body);
    } else {
      console.log('Replication from source suceeded \o/');
      console.log(JSON.stringify(body));
      replicationID = body._local_id;

      /*couchTarget.post "_replicate", repTargetToSource, (err, res, body)->
          if err? then callback err
          else if not body.ok
              console.log JSON.stringify body
              callback body
          else
              console.log 'Replication from target suceeded \o/'
              console.log JSON.stringify body
              callback err, replicationID
       */
      return callback(err, replicationID);
    }
  });
};

updateActiveRep = function(shareID, activeReplications, callback) {
  return db.get(shareID, function(err, doc) {
    if (err != null) {
      return callback(err);
    }
    doc.activeReplications = activeReplications;
    console.log('active rep : ' + JSON.stringify(activeReplications));
    return db.save(shareID, doc, function(err, res) {
      return callback(err);
    });
  });
};

saveReplication = function(rule, userID, replicationID, callback) {
  var isUpdate, _ref;
  if (!((rule != null) && (replicationID != null))) {
    return callback(null);
  }
  console.log('save replication ' + replicationID + ' with userid ' + userID);
  if (((_ref = rule.activeReplications) != null ? _ref.length : void 0) > 0) {
    isUpdate = false;
    return async.each(rule.activeReplications, function(rep, _callback) {
      if ((rep != null ? rep.userID : void 0) === userID) {
        rep.replicationID = replicationID;
        isUpdate = true;
      }
      return _callback(null);
    }, function(err) {
      console.log('is update : ' + isUpdate);
      if (!isUpdate) {
        rule.activeReplications.push({
          userID: userID,
          replicationID: replicationID
        });
      }
      return updateActiveRep(rule.id, rule.activeReplications, function(err) {
        return callback(err);
      });
    });
  } else {
    rule.activeReplications = [
      {
        userID: userID,
        replicationID: replicationID
      }
    ];
    return updateActiveRep(rule.id, rule.activeReplications, function(err) {
      return callback(err);
    });
  }
};

removeReplication = function(rule, replicationID, userID, callback) {
  if (!((rule != null) && (replicationID != null))) {
    return callback(null);
  }
  return cancelReplication(replicationID, function(err) {
    if (err != null) {
      return callback(err);
    }
    if (rule.activeReplications != null) {
      return async.each(rule.activeReplications, function(rep, _callback) {
        var i;
        if ((rep != null ? rep.userID : void 0) === userID) {
          i = rule.activeReplications.indexOf(rep);
          if (i > -1) {
            rule.activeReplications.splice(i, 1);
          }
          return updateActiveRep(rule.id, rule.activeReplications, function(err) {
            return _callback(err);
          });
        } else {
          return _callback(null);
        }
      }, function(err) {
        return callback(err);
      });
    } else {
      return updateActiveRep(rule.id, [], function(err) {
        return callback(err);
      });
    }
  });
};

cancelReplication = function(replicationID, callback) {
  var args, couchClient;
  couchClient = request.newClient("http://localhost:5984");
  args = {
    replication_id: replicationID,
    cancel: true
  };
  console.log('cancel args ' + JSON.stringify(args));
  return couchClient.post("_replicate", args, function(err, res, body) {
    if (err != null) {
      return callback(err);
    } else {
      console.log('Cancel replication');
      console.log(JSON.stringify(body));
      return callback();
    }
  });
};

getCozyAddressFromUserID = function(userID, callback) {
  if (userID != null) {
    return db.get(userID, function(err, user) {
      if (user != null) {
        console.log('user url : ' + user.url);
      }
      if (err != null) {
        return callback(err);
      } else {
        return callback(null, user.url);
      }
    });
  } else {
    return callback(null);
  }
};

getbinariesIds = function(doc) {
  var bin, ids, val;
  if (doc.binary != null) {
    ids = (function() {
      var _ref, _results;
      _ref = doc.binary;
      _results = [];
      for (bin in _ref) {
        val = _ref[bin];
        _results.push(val.id);
      }
      return _results;
    })();
    return ids;
  }
};

binaryHandling = function(mapRes, callback) {
  if ((mapRes.doc.binaries != null) || (mapRes.user.binaries != null)) {
    console.log('go insert binaries');
    return insertResults(mapRes, function(err) {
      if (err != null) {
        return callback(err);
      }
      return matching(mapRes, function(err, acls) {
        if (err != null) {
          return callback(err);
        }
        if (acls == null) {
          return callback(null);
        }
        return startShares([acls], function(err) {
          return callback(err);
        });
      });
    });
  } else {
    console.log('no binary in the doc');
    return callback(null);
  }
};

getActiveTasks = function(client, callback) {
  return client.get("_active_tasks", function(err, res, body) {
    var repIds, task, _i, _len;
    if ((err != null) || (body.length == null)) {
      return callback(err);
    } else {
      for (_i = 0, _len = body.length; _i < _len; _i++) {
        task = body[_i];
        if (task.replication_id) {
          repIds = task.replication_id;
        }
      }
      return callback(null, repIds);
    }
  });
};

module.exports.createRule = function(doc, callback) {};

module.exports.deleteRule = function(doc, callback) {};

module.exports.updateRule = function(doc, callback) {};

module.exports.selectDocPlug = function(id, callback) {
  return plug.selectSingleDoc(id, function(err, tuple) {
    return callback(err, tuple);
  });
};

module.exports.selectUserPlug = function(id, callback) {
  return plug.selectSingleUser(id, function(err, tuple) {
    return callback(err, tuple);
  });
};

saveRule = function(rule, callback) {
  var activeReplications, filterDoc, filterUser, id, name;
  id = rule._id;
  name = rule.name;
  filterDoc = rule.filterDoc;
  filterUser = rule.filterUser;
  if (rule.activeReplications) {
    activeReplications = rule.activeReplications;
  }
  return rules.push({
    id: id,
    name: name,
    filterDoc: filterDoc,
    filterUser: filterUser,
    activeReplications: activeReplications
  });
};

module.exports.insertRules = function(callback) {
  var insertShare;
  insertShare = function(rule, _callback) {
    return plug.insertShare(rule.id, '', function(err) {
      return _callback(err);
    });
  };
  return async.eachSeries(rules, insertShare, function(err) {
    if (err == null) {
      console.log('rules inserted');
    }
    return callback(err);
  });
};

module.exports.initRules = function(callback) {
  return db.view('sharingRule/all', function(err, rules) {
    if (err != null) {
      return callback(new Error("Error in view"));
    }
    rules.forEach(function(rule) {
      return saveRule(rule);
    });
    return callback();
  });
};

userInArray = function(array, userID) {
  var ar, _i, _len;
  if (array != null) {
    for (_i = 0, _len = array.length; _i < _len; _i++) {
      ar = array[_i];
      if (ar.userID === userID) {
        return true;
      }
    }
  }
  return false;
};

getRepID = function(array, userID) {
  var activeRep, _i, _len;
  if (array != null) {
    for (_i = 0, _len = array.length; _i < _len; _i++) {
      activeRep = array[_i];
      if (activeRep.userID === userID) {
        return activeRep.replicationID;
      }
    }
  }
};

shareIDInArray = function(array, shareID) {
  var ar, _i, _len;
  if (array != null) {
    for (_i = 0, _len = array.length; _i < _len; _i++) {
      ar = array[_i];
      if (((ar != null ? ar.doc : void 0) != null) && ar.doc.shareID === shareID) {
        return ar;
      }
      if (((ar != null ? ar.user : void 0) != null) && ar.user.shareID === shareID) {
        return ar;
      }
    }
  }
  return null;
};

getRuleById = function(shareID, callback) {
  var rule, _i, _len;
  for (_i = 0, _len = rules.length; _i < _len; _i++) {
    rule = rules[_i];
    if (rule.id === shareID) {
      return rule;
    }
  }
};

removeNullValues = function(array) {
  var i, _i, _ref, _results;
  if (array != null) {
    _results = [];
    for (i = _i = _ref = array.length - 1; _ref <= 0 ? _i <= 0 : _i >= 0; i = _ref <= 0 ? ++_i : --_i) {
      if (array[i] === null) {
        _results.push(array.splice(i, 1));
      } else {
        _results.push(void 0);
      }
    }
    return _results;
  }
};

removeDuplicates = function(array) {
  var key, res, value, _i, _ref, _results;
  if (array.length === 0) {
    return [];
  }
  res = {};
  for (key = _i = 0, _ref = array.length - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; key = 0 <= _ref ? ++_i : --_i) {
    res[array[key]] = array[key];
  }
  _results = [];
  for (key in res) {
    value = res[key];
    _results.push(value);
  }
  return _results;
};

convertTuples = function(tuples, callback) {
  var array, res, tuple, _i, _len;
  if (tuples != null) {
    array = [];
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      tuple = tuples[_i];
      res = {
        shareID: tuple[2],
        userParams: tuple[3]
      };
      array.push(res);
    }
    return array;
  }
};
