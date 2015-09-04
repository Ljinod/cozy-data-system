var BOOT_STATUS, DOCS, IS_INIT, USERS, authFP, bootStatus, buildACL, buildSelect, buildSelectDoc, close, deleteDoc, deleteMatch, deleteShare, deleteUser, init, insertDoc, insertDocs, insertShare, insertUser, isInit, java, jdbcJar, match, matchAll, plug, selectDocs, selectDocsByDocID, selectUsers, selectUsersByUserID;

java = require('java');

jdbcJar = './plug/plug_api.jar';

java.classpath.push(jdbcJar);

plug = java.newInstanceSync('org.cozy.plug.Plug');

IS_INIT = false;

BOOT_STATUS = 0;

USERS = 0;

DOCS = 1;

isInit = function() {
  return IS_INIT;
};

bootStatus = function() {
  return BOOT_STATUS;
};

buildSelect = function(table, tuples, callback) {
  var array, res, tuple, _i, _len;
  if (tuples != null) {
    array = [];
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      tuple = tuples[_i];
      res = {
        idPlug: tuple[0],
        userID: table === 0 ? tuple[1] : void 0,
        docID: table === 1 ? tuple[1] : void 0,
        shareID: tuple[2],
        userParams: tuple[3]
      };
      array.push(res);
    }
    return array;
  }
};

buildSelectDoc = function(tuples, callback) {
  var array, res, tuple, _i, _len;
  if (tuples != null) {
    array = [];
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      tuple = tuples[_i];
      res = {
        idPlug: tuple[0],
        docID: tuple[1],
        shareID: tuple[2],
        userParams: tuple[3]
      };
      array.push(res);
    }
    return array;
  }
};

buildACL = function(tuples, shareid, callback) {
  var res, tuple, userInArray, _i, _len;
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
  if (tuples != null) {
    res = {
      shareID: shareid,
      users: [],
      docIDs: []
    };
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      tuple = tuples[_i];
      if (!userInArray(res.users, tuple[0])) {
        res.users.push({
          userID: tuple[0]
        });
      }
      if (!(res.users.length > 1)) {
        res.docIDs.push(tuple[1]);
      }
    }
    return callback(res);
  } else {
    return callback(null);
  }
};

init = function(callback) {
  var timeoutProtect;
  timeoutProtect = setTimeout((function() {
    timeoutProtect = null;
    return callback({
      error: 'PlugDB timed out'
    });
  }), 30000);
  return plug.plugInit('/dev/ttyACM0', function(err, status) {
    if (timeoutProtect) {
      clearTimeout(timeoutProtect);
      if (err == null) {
        console.log('PlugDB is ready');
        IS_INIT = true;
        BOOT_STATUS = status;
      }
      return callback(err);
    }
  });
};

insertDocs = function(ids, callback) {
  var array;
  array = java.newArray('java.lang.String', ids);
  plug.plugInsertDocs(array, function(err) {
    callback(err);
  });
};

insertDoc = function(docid, shareid, userParams, callback) {
  return plug.plugInsertDoc(docid, shareid, userParams, function(err) {
    return callback(err);
  });
};

insertUser = function(userid, shareid, userParams, callback) {
  return plug.plugInsertUser(userid, shareid, userParams, function(err) {
    return callback(err);
  });
};

insertShare = function(shareid, description, callback) {
  return plug.plugInsertShare(shareid, description, function(err) {
    return callback(err);
  });
};

deleteDoc = function(idGlobal, callback) {
  return plug.plugDeleteDoc(idGlobal, function(err) {
    return callback(err);
  });
};

deleteUser = function(idGlobal, callback) {
  return plug.plugDeleteUser(idGlobal, function(err) {
    return callback(err);
  });
};

deleteShare = function(idGlobal, callback) {
  return plug.plugDeleteShare(idGlobal, function(err) {
    return callback(err);
  });
};

selectDocs = function(callback) {
  plug.plugSelectDocs(function(err, results) {
    callback(err, results);
  });
};

selectUsers = function(callback) {
  plug.plugSelectUsers(function(err, results) {
    callback(err, results);
  });
};

selectDocsByDocID = function(docid, callback) {
  return plug.plugSelectDocsByDocID(docid, function(err, tuples) {
    if (err != null) {
      return callback(err);
    } else {
      return buildSelect(DOCS, tuples, function(err, result) {
        return callback(err, result);
      });
    }
  });
};

selectUsersByUserID = function(userid, callback) {
  return plug.plugSelectUsersByUserID(userid, function(err, tuples) {
    if (err != null) {
      return callback(err);
    } else {
      return buildSelect(USERS, tuples, function(err, result) {
        return callback(err, result);
      });
    }
  });
};

matchAll = function(matchingType, id, shareid, callback) {
  return plug.plugMatchAll(matchingType, id, shareid, function(err, tuples) {
    return buildACL(tuples, shareid, function(acl) {
      return callback(err, acl);
    });
  });
};

match = function(matchingType, id, shareid, callback) {
  return plug.plugMatch(matchingType, id, shareid, function(err, result) {
    return callback(err, result);
  });
};

deleteMatch = match = function(matchingType, idPlug, shareid, callback) {
  return plug.plugDeleteMatch(matchingType, idPlug, shareid, function(err, tuples) {
    return buildACL(tuples, shareid, function(acl) {
      return callback(err, acl);
    });
  });
};

close = function(callback) {
  console.log('go close');
  return plug.plugClose(function(err) {
    if (err) {
      return callback(err);
    } else {
      IS_INIT = false;
      return callback(null);
    }
  });
};

authFP = function(callback) {
  plug.plugFPAuthentication(function(err, authID) {
    callback(err, authID);
  });
};

exports.USERS = USERS;

exports.DOCS = DOCS;

exports.isInit = isInit;

exports.bootStatus = bootStatus;

exports.init = init;

exports.insertDocs = insertDocs;

exports.insertDoc = insertDoc;

exports.insertUser = insertUser;

exports.insertShare = insertShare;

exports.deleteDoc = deleteDoc;

exports.deleteUser = deleteUser;

exports.deleteShare = deleteShare;

exports.selectDocs = selectDocs;

exports.selectUsers = selectUsers;

exports.selectDocsByDocID = selectDocsByDocID;

exports.selectUsersByUserID = selectUsersByUserID;

exports.matchAll = matchAll;

exports.match = match;

exports.deleteMatch = deleteMatch;

exports.close = close;

exports.authFP = authFP;
