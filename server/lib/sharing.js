var async, db, insertResults, mapDoc, mapDocInRules, plug, rules, saveRule;

plug = require('./plug');

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

rules = [];

module.exports.mapDocOnInsert = function(doc, id, callback) {
  return mapDocInRules(doc, id, function(err, mapResults) {
    if (err) {
      return callback(err);
    } else {
      return async.map(mapResults, insertResults, function(err) {
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
      if (mapResult.user != null) {
        return plug.insertUser(mapResult.docid, mapResult.shareid, mapResult.userDesc, function(err) {
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
        console.log('doc maped !! ' + JSON.stringify(docMaped));
      }
      if (docMaped) {
        saveResult(id, rule.id, filterDoc.userParam, true);
      }
      return mapDoc(doc, id, rule.id, filterUser, function(userMaped) {
        if (userMaped) {
          console.log('user maped !! ' + JSON.stringify(userMaped));
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
    var i, res, results, _i, _len;
    results = Array.prototype.slice.call(mapResults, 0);
    for (i = _i = 0, _len = results.length; _i < _len; i = ++_i) {
      res = results[i];
      if (res === null) {
        results.splice(i, 1);
      }
    }
    return callback(err, results);
  });
};

mapDoc = function(doc, docid, shareid, filter, callback) {
  var ret;
  console.log('eval ' + JSON.stringify(filter.rule + ' for the doc ' + JSON.stringify(doc)));
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

module.exports.createRule = function(doc, callback) {};

module.exports.deleteRule = function(doc, callback) {};

module.exports.updateRule = function(doc, callback) {};

saveRule = function(rule, callback) {
  var filterDoc, filterUser, id, name;
  id = rule._id;
  name = rule.name;
  filterDoc = rule.filterDoc;
  filterUser = rule.filterUser;
  return rules.push({
    id: id,
    name: name,
    filterDoc: filterDoc,
    filterUser: filterUser
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
