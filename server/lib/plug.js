var authFP, close, init, insertDoc, insertDocs, insertShare, insertUser, java, jdbcJar, match, matchAll, plug, selectDocs, selectSingleDoc, selectSingleUser, selectUsers;

java = require('java');

jdbcJar = './plug/plug_api.jar';

java.classpath.push(jdbcJar);

plug = java.newInstanceSync('org.cozy.plug.Plug');

init = function(callback) {
  var timeoutProtect;
  timeoutProtect = setTimeout((function() {
    timeoutProtect = null;
    return callback({
      error: 'PlugDB timed out'
    });
  }), 30000);
  return plug.plugInit('/dev/ttyACM0', function(err) {
    if (timeoutProtect) {
      clearTimeout(timeoutProtect);
      console.log('PlugDB ready');
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

selectSingleDoc = function(docid, callback) {
  plug.plugSelectSingleDoc(docid, function(err, result) {
    callback(err, result);
  });
};

selectSingleUser = function(userid, callback) {
  plug.plugSelectSingleUser(userid, function(err, result) {
    callback(err, result);
  });
};

matchAll = function(matchingType, id, shareid, callback) {
  return plug.plugMatchAll(matchingType, id, shareid, function(err, result) {
    return callback(err, result);
  });
};

match = function(matchingType, id, shareid, callback) {
  return plug.plugMatch(matchingType, id, shareid, function(err, result) {
    return callback(err, result);
  });
};

close = function(callback) {
  plug.plugClose(function(err) {
    callback(err);
  });
};

authFP = function(callback) {
  plug.plugFPAuthentication(function(err, authID) {
    callback(err, authID);
  });
};

exports.MATCH_USERS = 0;

exports.MATCH_DOCS = 1;

exports.init = init;

exports.insertDocs = insertDocs;

exports.insertDoc = insertDoc;

exports.insertUser = insertUser;

exports.insertShare = insertShare;

exports.selectDocs = selectDocs;

exports.selectUsers = selectUsers;

exports.selectSingleDoc = selectSingleDoc;

exports.selectSingleUser = selectSingleUser;

exports.matchAll = matchAll;

exports.match = match;

exports.close = close;

exports.authFP = authFP;
