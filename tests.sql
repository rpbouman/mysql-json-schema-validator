delimiter //

drop procedure p_validate_json_schema_test
//

create procedure p_validate_json_schema_test(
  p_json  JSON
, p_rules JSON
, p_passfail BOOL
, p_message TEXT
)
begin
  DECLARE v_message_text TEXT;
  DECLARE v_passfail BOOL DEFAULT TRUE;
  DECLARE v_cno INT UNSIGNED;
  DECLARE continue handler FOR SQLSTATE '42000'
    BEGIN
      SET v_passfail = FALSE;
      GET CURRENT DIAGNOSTICS CONDITION 1 v_message_text = MESSAGE_TEXT;
      IF v_message_text != p_message THEN
        SET v_passfail = !p_passfail;
      END IF;
    END;

  CALL p_validate_json_schema(p_json, p_rules);
  IF v_passfail != p_passfail THEN
    SELECT 'Failed!', v_message_text, p_json, p_rules;
  ELSE
    SELECT 'Success!';
  END IF;
end;
//

delimiter ;

-- test type of rules collection
call p_validate_json_schema_test(
  '[]', '{}', FALSE,
  'ERROR 1644 (42000): Rules parameter must be an ARRAY type. Found: OBJECT.'
);

call p_validate_json_schema_test(
  '[]', '[]', TRUE, ''
);

-- test type of rules
call p_validate_json_schema_test(
  '[]', '[1]', FALSE,
  'ERROR 1644 (42000): Rule 1 must be of the OBJECT type. Found: INTEGER'
);

-- ascertain rules have a "path" property
call p_validate_json_schema_test(
  '[]', '[{}]', FALSE,
  'ERROR 1644 (42000): Rule 1 must specify a $.path property.'
);

-- ascertain the type of the "path" property
call p_validate_json_schema_test('[]', '[{
  "path": 1
}]', FALSE,
  'ERROR 1644 (42000): Property$.path of rule 1 at path 1 must be of the STRING type. Found: INTEGER.'
);

-- check that the specified "path" is checked
call p_validate_json_schema_test('[]', '[{
  "path": ".bla"
}]', FALSE,
  'ERROR 1644 (42000): Non-optional item at path .bla not found.'
);

-- check the type of the optional property
call p_validate_json_schema_test('[]', '[{
  "path": ".bla",
  "optional": 1
}]', FALSE,
  'ERROR 1644 (42000): Property $.optional of rule 1 at path ".bla" must be of the BOOLEAN type. Found: INTEGER.'
);

-- check that optional properties may be omitted
call p_validate_json_schema_test('[]', '[{
  "path": ".bla",
  "optional": true
}]', TRUE, '');

-- check that explicit non-optional properties may not be omitted
call p_validate_json_schema_test('[]', '[{
  "path": ".bla",
  "optional": false
}]', FALSE,
  'ERROR 1644 (42000): Non-optional item at path .bla not found.'
);

-- check that doc is considered valid for specified property
call p_validate_json_schema_test('{
  "bla": 1
}', '[{
  "path": ".bla"
}]', TRUE, '');

-- check that doc is considered valid for specified property of particular tpe
call p_validate_json_schema_test('{
  "bla": 1
}', '[{
  "path": ".bla",
  "type": "INTEGER"
}]', TRUE, '');

-- check that doc is considered valid for specified property that is one of specified types
call p_validate_json_schema_test('{
  "bla": 1
}', '[{
  "path": ".bla",
  "type": ["INTEGER", "DECIMAL"]
}]', TRUE, '');

-- check that doc is considered valid for specified property that is one of specified types
call p_validate_json_schema_test('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": ["INTEGER", "DOUBLE"]
}]', TRUE, '');

-- check that doc is considered invalid if specified property has not one of specified types
call p_validate_json_schema_test('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": ["INTEGER", "DECIMAL"]
}]', FALSE,
  'ERROR 1644 (42000): Item at path .bla should have one of the types ["INTEGER", "DECIMAL"]. Found: DOUBLE.'
);

-- check that doc is considered invalid if specified property as explicitly excluded type
call p_validate_json_schema_test('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": ["INTEGER", "DOUBLE"]
}]', TRUE, '');

-- check that doc is considered invalid if specified property as explicitly excluded type
call p_validate_json_schema_test('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": {"INTEGER": true, "DOUBLE": false}
}]', FALSE, 'ERROR 1644 (42000): Item at path .bla has an invalid type. Found: DOUBLE.'
);

-- check that doc is considered valid if specified property as explicitly included type
call p_validate_json_schema_test('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": {"INTEGER": false, "DOUBLE": true}
}]', TRUE, '');

-- check that doc is considered invalid if specified non-nullable property is null
call p_validate_json_schema_test('{
  "bla": null
}', '[{
  "path": ".bla",
  "type": {"INTEGER": false, "DOUBLE": true}
}]', FALSE,
  'ERROR 1644 (42000): Non-nullable item at path .bla is null.'
);

-- check that doc is considered valid if specified nullable property is null
call p_validate_json_schema_test('{
  "bla": null
}', '[{
  "path": ".bla",
  "nullable": true,
  "type": {"INTEGER": false, "DOUBLE": true}
}]', TRUE, '');

-- check that rule is considered invalid if specified minvalue is of other type than property value
call p_validate_json_schema_test('{
  "bla": 1
}', '[{
  "path": ".bla",
  "minvalue": 1.0
}]', FALSE,
  'ERROR 1644 (42000): Property $.minvalue of rule 1 at path ".bla" must be of type INTEGER. Found: DOUBLE.'
);

-- check that doc is considered invalid if specified minvalue exceeds property value
call p_validate_json_schema_test('{
  "bla": 1
}', '[{
  "path": ".bla",
  "minvalue": 2
}]', FALSE,
  'ERROR 1644 (42000): Item at path .bla is smaller than $.minvalue.'
);

-- check that rule is considered invalid if specified maxvalue is of other type than property value
call p_validate_json_schema_test('{
  "bla": 1
}', '[{
  "path": ".bla",
  "maxvalue": 1.0
}]', FALSE,
  'ERROR 1644 (42000): Property $.maxvalue of rule 1 at path ".bla" must be of type INTEGER. Found: DOUBLE.'
);

-- check that doc is considered invalid if property value exceeds specified maxvalue
call p_validate_json_schema_test('{
  "bla": 2
}', '[{
  "path": ".bla",
  "maxvalue": 1
}]', FALSE,
  'ERROR 1644 (42000): Item at path .bla is larger than $.maxvalue.'
);

-- check that rule is considered invalid if minvalue exceeds maxvalue
call p_validate_json_schema_test('{
  "bla": 5
}', '[{
  "path": ".bla",
  "minvalue": 2,
  "maxvalue": 1
}]', FALSE,
  'ERROR 1644 (42000): Property $.maxvalue of rule 1 at path ".bla" is less than $.minvalue.'
);

-- check that doc is considered valid if value is between minvalue and maxvalue (inclusive)
call p_validate_json_schema_test('{
  "bla": 2
}', '[{
  "path": ".bla",
  "minvalue": 2,
  "minvalue": 2
}]', TRUE, ''
);

-- check that doc is considered invalid if value has length less than minlenght
call p_validate_json_schema_test('{
  "bla": "string of length 19"
}', '[{
  "path": ".bla",
  "minlength": 20,
  "maxlength": 21
}]', FALSE,
  'ERROR 1644 (42000): Length of item at path .bla is 19 which is less than the specied $.minlength of 20.'
);

-- check that doc is considered invalid if value has length more than than maxlength
call p_validate_json_schema_test('{
  "bla": "string of length 19"
}', '[{
  "path": ".bla",
  "minlength": 10,
  "maxlength": 18
}]', FALSE,
  'ERROR 1644 (42000): Length of item at path .bla is 19 which is more than the specied $.maxlength of 18.'
);

-- check that rule is considered invalid if minlenght exceeds maxlength
call p_validate_json_schema_test('{
  "bla": "string of length 19"
}', '[{
  "path": ".bla",
  "minlength": 19,
  "maxlength": 18
}]', FALSE,
  'ERROR 1644 (42000): Property $.maxlength of rule 1 at path ".bla" is 18 which is less than the value specified for $.minlength which is 19.'
);

-- check that doc is considered invalid if value length is in between minlength exceeds maxlength
call p_validate_json_schema_test('{
  "bla": "string of length 19"
}', '[{
  "path": ".bla",
  "minlength": 19,
  "maxlength": 21
}]', TRUE, ''
);

-- check that doc is considered valid if value is in specified array of values
call p_validate_json_schema_test('{
  "bla": "boe"
}', '[{
  "path": ".bla",
  "values": ["boe", "bla"]
}]', TRUE, ''
);

-- check that doc is considered valid if value is in specified array of values
call p_validate_json_schema_test('{
  "bla": "bla"
}', '[{
  "path": ".bla",
  "values": ["boe", "bla"]
}]', TRUE, ''
);

-- check that doc is considered invalid if value is not in specified array of values
call p_validate_json_schema_test('{
  "bla": "bla"
}', '[{
  "path": ".bla",
  "values": ["foo", "bar"]
}]', FALSE,
  'ERROR 1644 (42000): Item at path .bla must be one of the values ["foo", "bar"] specified in $.values.'
);

-- check that extra rules are checked when property is of particular type
call p_validate_json_schema_test('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": {
    "STRING": {
      "minlength": 1
    },
    "DOUBLE": {
      "minvalue": 2.0
    }
  }
}]', FALSE,
  'ERROR 1644 (42000): Item at path .bla is smaller than $.minvalue.'
);

-- check that extra rules are checked when property is of particular type
call p_validate_json_schema_test('{
  "bla": ""
}', '[{
  "path": ".bla",
  "type": {
    "STRING": {
      "minlength": 1
    },
    "DOUBLE": {
      "minvalue": 2
    }
  }
}]', FALSE,
  'ERROR 1644 (42000): Length of item at path .bla is 0 which is less than the specied $.minlength of 1.'
);

-- check that subrules are tested:
call p_validate_json_schema_test('{
  "bla": {
    "boe": 1
  }
}', '[{
  "path": ".bla",
  "rules": [{
    "path": ".boe",
    "type": "STRING"
  }]
}]', FALSE,
  'ERROR 1644 (42000): Item at path .bla.boe should be of type "STRING". Found: INTEGER.'
);
