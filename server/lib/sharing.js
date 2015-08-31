var async, cancelReplication, db, getActiveTasks, getCozyAddressFromUserID, getRepID, getRuleById, insertResults, mapDoc, mapDocInRules, plug, removeDuplicates, removeNullValues, removeReplication, replicateDocs, request, rules, saveReplication, saveRule, shareDocs, startShares, updateActiveRep, userInArray, userSharing;

plug = require('./plug');

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

request = require('request-json');

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
    mapResults = Array.prototype.slice.call(mapResults);
    removeNullValues(mapResults);
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
  var matching;
  matching = function(mapResult, _callback) {
    var id, matchType;
    if (mapResult.docid != null) {
      matchType = plug.MATCH_USERS;
      id = mapResult.docid;
    } else {
      matchType = plug.MATCH_DOCS;
      id = mapResult.userid;
    }
    return plug.matchAll(matchType, id, mapResult.shareid, function(err, acl) {
      if (acl != null) {
        acl = Array.prototype.slice.call(acl);
        acl.unshift(mapResult.shareid);
      }
      return _callback(err, acl);
    });
  };
  if (mapResults != null) {
    return async.mapSeries(mapResults, matching, function(err, acls) {
      if (err) {
        return callback(err);
      } else {
        removeNullValues(acls);
        if ((acls != null) && acls.length > 0) {
          return startShares(acls, function(err) {
            return callback(err);
          });
        } else {
          return callback(null);
        }
      }
    });
  } else {
    return callback(null);
  }
};

startShares = function(acls, callback) {
  var buildShareData, sharingProcess;
  buildShareData = function(acl, _callback) {
    var docID, i, id, share, userID, _i, _len;
    share = {
      shareID: null,
      users: [],
      docIDs: []
    };
    for (i = _i = 0, _len = acl.length; _i < _len; i = ++_i) {
      id = acl[i];
      if (i === 0) {
        share.shareID = id;
      } else {
        userID = id[0];
        docID = id[1];
        if (!userInArray(share.users, userID)) {
          share.users.push({
            userID: userID
          });
        }
        if (!(share.users.length > 1)) {
          share.docIDs.push(docID);
        }
      }
    }
    return _callback(null, share);
  };
  sharingProcess = function(share, _callback) {
    var user, _i, _len, _ref, _results;
    _ref = share.users;
    _results = [];
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      user = _ref[_i];
      _results.push(getCozyAddressFromUserID(user.userID, function(err, url) {
        user.target = url;
        return userSharing(share.shareID, user, share.docIDs, function(err) {
          return callback(err);
        });
      }));
    }
    return _results;
  };
  return async.map(acls, buildShareData, function(err, shares) {
    console.log('shares : ' + JSON.stringify(shares));
    return async.each(shares, sharingProcess, function(err) {
      return callback(err);
    });
  });
};

userSharing = function(shareID, user, ids, callback) {
  var replicationID, rule;
  console.log('user id : ' + user.userID);
  rule = getRuleById(shareID);
  if (rule != null) {
    replicationID = getRepID(rule.activeReplications, user.userID);
    console.log('get rep id : ' + replicationID);
    if (replicationID != null) {
      return cancelReplication(replicationID, function(err) {
        if (err != null) {
          return callback(err);
        } else {
          return shareDocs(user, ids, rule, function(err) {
            return callback(err);
          });
        }
      });
    } else {
      return shareDocs(user, ids, rule, function(err) {
        return callback(err);
      });
    }
  } else {
    return callback(null);
  }
};

shareDocs = function(user, ids, rule, callback) {
  return replicateDocs(user.target, ids, function(err, repID) {
    if (err != null) {
      return callback(err);
    } else {
      return saveReplication(rule, user.userID, repID, function(err) {
        return callback(err);
      });
    }
  });
};

replicateDocs = function(target, ids, callback) {
  var couchClient, couchTarget, repSourceToTarget, repTargetToSource, sourceURL, targetURL;
  console.log('lets replicate ' + ids + ' on target ' + target);
  couchClient = request.newClient("http://localhost:5984");
  sourceURL = "http://192.168.50.4:5984/cozy";
  targetURL = "http://pzjWbznBQPtfJ0es6cvHQKX0cGVqNfHW:" + "NPjnFATLxdvzLxsFh9wzyqSYx4CjG30U" + "@192.168.50.5:5984/cozy";
  couchTarget = request.newClient(targetURL);
  repSourceToTarget = {
    source: "cozy",
    target: targetURL,
    continuous: true,
    doc_ids: ids
  };
  repTargetToSource = {
    source: "cozy",
    target: sourceURL,
    continuous: true,
    doc_ids: ids
  };
  return couchClient.post("_replicate", repSourceToTarget, function(err, res, body) {
    var replicationID;
    if (err) {
      return callback(err);
    } else if (!body.ok) {
      console.log(JSON.stringify(body));
      return callback(body);
    } else {
      console.log('Replication from source suceeded \o/');
      console.log(JSON.stringify(body));
      replicationID = body._local_id;
      return couchTarget.post("_replicate", repTargetToSource, function(err, res, body) {
        if (err) {
          return callback(err);
        } else if (!body.ok) {
          console.log(JSON.stringify(body));
          return callback(body);
        } else {
          console.log('Replication from target suceeded \o/');
          console.log(JSON.stringify(body));
          return callback(err, replicationID);
        }
      });
    }
  });
};

saveReplication = function(rule, userID, replicationID, callback) {
  if ((rule != null) && (replicationID != null)) {
    if (rule.activeReplications != null) {
      rule.activeReplications.push({
        userID: userID,
        replicationID: replicationID
      });
      return updateActiveRep(rule.id, rule.activeReplications, true, function(err) {
        return callback(err);
      });
    } else {
      rule.activeReplications = [
        {
          userID: userID,
          replicationID: replicationID
        }
      ];
      return updateActiveRep(rule.id, rule.activeReplications, false, function(err) {
        return callback(err);
      });
    }
  } else {
    return callback(null);
  }
};

updateActiveRep = function(shareID, activeReplications, merge, _callback) {
  if (merge) {
    return db.merge(shareID, {
      activeReplications: activeReplications
    }, function(err, res) {
      if (res) {
        console.log('merge res : ' + JSON.stringify(res));
      }
      return callback(err);
    });
  } else {
    return db.get(shareID, function(err, doc) {
      if (err) {
        return callback(err);
      } else {
        doc.activeReplications = activeReplications;
        return db.save(shareID, doc, function(err, res) {
          if (res) {
            console.log('res save : ' + JSON.stringify(res));
          }
          return callback(err);
        });
      }
    });
  }
};

removeReplication = function(rule, replicationID, callback) {
  return cancelReplication(replicationID, function(err) {
    var i, rep, _i, _len, _ref, _results;
    if (err != null) {
      return callback(err);
    } else {
      if (rule.activeReplications != null) {
        _ref = rule.activeReplication;
        _results = [];
        for (i = _i = 0, _len = _ref.length; _i < _len; i = ++_i) {
          rep = _ref[i];
          if (rep.replicationID === replicationID) {
            rule.activeReplications.slice(i, 1);
            _results.push(updateActiveRep(rule.id, rule.activeReplications, function(err) {
              return callback(err);
            }));
          } else {
            _results.push(void 0);
          }
        }
        return _results;
      } else {
        return updateActiveRep(rule.id, [], function(err) {
          return callback(err);
        });
      }
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
  console.log('args ' + JSON.stringify(args));
  return couchClient.post("_replicate", args, function(err, res, body) {
    if (err) {
      return callback(err);
    } else if (!body.ok) {
      console.log(JSON.stringify(body));
      return callback(body);
    } else {
      console.log('Cancel replication ok');
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

getActiveTasks = function(client, callback) {
  return client.get("_active_tasks", function(err, res, body) {
    var repIds, task, _i, _len;
    if (err || (body.length == null)) {
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
  _results = [];
  for (i = _i = _ref = array.length - 1; _ref <= 0 ? _i <= 0 : _i >= 0; i = _ref <= 0 ? ++_i : --_i) {
    if (array[i] === null) {
      _results.push(array.splice(i, 1));
    } else {
      _results.push(void 0);
    }
  }
  return _results;
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
