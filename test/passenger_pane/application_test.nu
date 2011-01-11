(load "test_helper")

(describe "Application" `(
  (it "initializes with attributes" (do ()
    (set attributes (NSMutableDictionary dictionary))
    (attributes setValue:"test.host" forKey:"host")
    (attributes setValue:"assets.test.host" forKey:"aliases")
    (attributes setValue:"/path/to/test" forKey:"path")
    (attributes setValue:"production" forKey:"environment")
    (attributes setValue:"/path/to/test.conf" forKey:"config_filename")
    (set application ((Application alloc) initWithAttributes:attributes))
    
    (~ application host should be:"test.host")
    (~ application aliases should be:"assets.test.host")
    (~ application path should be:"/path/to/test")
    (~ application environment should be:1)
    (~ application configFilename should be:"/path/to/test.conf")
  ))
  
  (it "initializes with attributes, even when the environment is not passed" (do ()
    (set attributes (NSMutableDictionary dictionary))
    (attributes setValue:"test.host" forKey:"host")
    (set application ((Application alloc) initWithAttributes:attributes))
    (~ application host should be:"test.host")
  ))
))

((Bacon sharedInstance) run)