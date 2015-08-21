var async, cancelReplication, db, getActiveTasks, getCozyAddressFromUserID, insertResults, mapDoc, mapDocInRules, matching, plug, rules, saveReplication, saveRule, shareDocs;

plug = require('./plug');

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

rules = [];

module.exports.mapDocOnInsert = function(doc, id, callback) {
  return mapDocInRules(doc, id, function(err, mapResults) {
    if (err) {
      return callback(err);
    } else {
      return async.eachSeries(mapResults, insertResults, function(err) {
        console.log('results : ' + JSON.stringify(mapResults));
        return callback(err, mapResults);
      });
    }
  });
};

insertResults = function(mapResult, callback) {
  return async.series([
    function(_callback) {
      if (mapResult.docid != null) {
        return plug.insertDoc(mapResult.docid, mapResult.shareid, mapResult.userDesc, function(err) {
          if (err == null) {
            console.log("doc " + mapResult.docid + " inserted in PlugDB");
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
      if (mapResult.userid != null) {
        return plug.insertUser(mapResult.userid, mapResult.shareid, mapResult.userDesc, function(err) {
          if (err == null) {
            console.log("user " + mapResult.userid + " inserted in PlugDB");
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

mapDocInRules = function(doc, id, callback) {
  var evalRule;
  evalRule = function(rule, _callback) {
    var filterDoc, filterUser, mapResult, saveResult;
    mapResult = {
      docid: null,
      userid: null,
      shareid: null,
      userParams: null
    };
    saveResult = function(id, shareid, userParams, isDoc) {
      if (isDoc) {
        mapResult.docid = id;
      } else {
        mapResult.userid = id;
      }
      mapResult.shareid = shareid;
      return mapResult.userParams = userParams;
    };
    filterDoc = rule.filterDoc;
    filterUser = rule.filterUser;
    return mapDoc(doc, id, rule.id, filterDoc, function(docMaped) {
      if (docMaped) {
        console.log('doc maped !! ');
      }
      if (docMaped) {
        saveResult(id, rule.id, filterDoc.userParam, true);
      }
      return mapDoc(doc, id, rule.id, filterUser, function(userMaped) {
        if (userMaped) {
          console.log('user maped !! ');
        }
        if (userMaped) {
          saveResult(id, rule.id, filterUser.userParam, false);
        }
        if ((mapResult.docid == null) && (mapResult.userid == null)) {
          return _callback(null, null);
        } else {
          return _callback(null, mapResult);
        }
      });
    });
  };
  return async.map(rules, evalRule, function(err, mapResults) {
    var i, _i, _ref;
    mapResults = Array.prototype.slice.call(mapResults);
    for (i = _i = _ref = mapResults.length - 1; _ref <= 0 ? _i <= 0 : _i >= 0; i = _ref <= 0 ? ++_i : --_i) {
      if (mapResults[i] === null) {
        mapResults.splice(i, 1);
      }
    }
    return callback(err, mapResults);
  });
};

mapDoc = function(doc, docid, shareid, filter, callback) {
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

module.exports.matchAfterInsert = function(mapResults, callback) {
  if (mapResults != null) {
    return async.mapSeries(mapResults, matching, function(err, acls) {
      if (acls) {
        console.log('acls : ' + JSON.stringify(acls));
      }
      return callback(err, acls);
    });
  } else {
    return callback(null);
  }
};

matching = function(mapResult, callback) {
  return async.series([
    function(_callback) {
      if (mapResult.docid != null) {
        return plug.matchAll(plug.MATCH_USERS, mapResult.docid, mapResult.shareid, function(err, acls) {
          if (acls != null) {
            console.log('res match : ' + JSON.stringify(acls));
          }
          return _callback(err, acls);
        });
      } else {
        return _callback(null);
      }
    }, function(_callback) {
      if (mapResult.userid != null) {
        return plug.matchAll(plug.MATCH_DOCS, mapResult.userid, mapResult.shareid, function(err, acls) {
          if (acls != null) {
            console.log('res match : ' + JSON.stringify(acls));
          }
          return _callback(err, acls);
        });
      } else {
        return _callback(null);
      }
    }
  ], function(err, matchResults) {
    if (matchResults != null) {
      console.log('match results : ' + JSON.stringify(matchResults));
    }
    return callback(err, matchResults);
  });
};

shareDocs = function(target, ids) {
  var couchClient, repSourceToTarget, repTargetToSource, sourceURL, targetURL;
  couchClient = request.newClient("http://localhost:5984");
  sourceURL = "http://localhost:5984/cozy";
  targetURL = "http://pzjWbznBQPtfJ0es6cvHQKX0cGVqNfHW:NPjnFATLxdvzLxsFh9wzyqSYx4CjG30U@192.168.50.5:5984/cozy";
  repSourceToTarget = {
    source: "cozy",
    target: targetURL,
    continuous: true,
    doc_ids: ids
  };
  repTargetToSource = {
    source: "cozy",
    target: source,
    continuous: true,
    doc_ids: ids
  };
  return couchClient.post("_replicate", repSourceToTarget, function(err, res, body) {
    var replicationID;
    if (err || !body.ok) {
      console.log(JSON.stringify(body));
      console.log("Replication from source failed");
      return callback(err);
    } else {
      console.log('Replication from source suceeded \o/');
      console.log(JSON.stringify(body));
      replicationID = body._local_id;
      return couchTarget.post("_replicate", repTargetToSource, function(err, res, body) {
        if (err || !body.ok) {
          console.log(JSON.stringify(body));
          console.log("Replication from target failed");
          return callback(err);
        } else {
          console.log('Replication from target suceeded \o/');
          console.log(JSON.stringify(body));
          return callback(err, replicationID);
        }
      });
    }
  });
};

saveReplication = function(rule, replicationID, callback) {
  if ((rule != null) && (replicationID != null)) {
    if (rule.activeReplications) {
      rule.activeReplications.push(replicationID);
    } else {
      rule.activeReplications = [replicationID];
    }
    console.log('active replications : ' + JSON.stringify(rule.activeReplications));
    db.save(ruleID, {
      activeReplications: rule.activeReplications
    }, function(err, res) {
      console.log(JSON.stringify(res));
      return callback(err, res);
    });
  }
  return callback(null);
};

getCozyAddressFromUserID = function(userID, callback) {};

cancelReplication = function(client, replicationID, callback) {
  return client.post("_replicate", {
    replication_id: replicationID,
    cancel: true
  }, function(err, res, body) {
    if (err || !body.ok) {
      console.log("Cancel replication failed");
      return callback(err);
    } else {
      console.log('Cancel replication ok');
      return callback();
    }
  });
};

getActiveTasks = function(client, callback) {
  return client.get("_active_tasks", function(err, res, body) {
    var repIds, task;
    if (err || (body.length == null)) {
      return callback(err);
    } else {
      repIds = (function() {
        var _i, _len, _results;
        _results = [];
        for (_i = 0, _len = body.length; _i < _len; _i++) {
          task = body[_i];
          if (task.replication_id) {
            _results.push(task.replication_id);
          }
        }
        return _results;
      })();
      return callback(null, repIds);
    }
  });
};

module.exports.createRule = function(doc, callback) {};

module.exports.deleteRule = function(doc, callback) {};

module.exports.updateRule = function(doc, callback) {};

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
    if (!err) {
      console.log('sharing rules inserted in plug db');
    }
    return callback(err);
  });
};

module.exports.initRules = function(callback) {
  return db.view('sharingRules/all', function(err, rules) {
    if (err != null) {
      return callback(new Error("Error in view"));
    }
    rules.forEach(function(rule) {
      return saveRule(rule);
    });
    return callback();
  });
};
