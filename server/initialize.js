var log;

log = require('printit')({
  prefix: 'init'
});

module.exports = function(app, server, callback) {
  var feed, init;
  feed = require('./lib/feed');
  feed.initialize(server);
  init = require('./lib/init');
  return init.removeDocWithoutDocType(function(err) {
    if (err != null) {
      log.error(err);
    }
    return init.removeLostBinaries(function(err) {
      if (err != null) {
        log.error(err);
      }
      init.addThumbs(function(err) {
        if (err != null) {
          log.error(err);
        }
        return init.addAccesses(function(err) {
          if (err != null) {
            log.error(err);
          }
          return init.initPlugDB(function(err) {
            if (err != null) {
              log.error(err);
            }
            return init.addSharingRules(function(err) {
              if (err != null) {
                log.error(err);
              }
              return init.insertSharesPlugDB(function(err) {
                if (err != null) {
                  return log.error(err);
                }
              });
            });
          });
        });
      });
      if (callback != null) {
        return callback(app, server);
      }
    });
  });
};
