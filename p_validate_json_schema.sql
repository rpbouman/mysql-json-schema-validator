delimiter //

DROP PROCEDURE p_validate_json_schema;
//

CREATE PROCEDURE p_validate_json_schema(
  p_json  JSON
, p_rules JSON
)
BEGIN
  DECLARE cond_rule_error CONDITION FOR SQLSTATE '42000';
  DECLARE cond_validation_error CONDITION FOR SQLSTATE '42000';

  -- property constants
  DECLARE v_prop_path     CHAR(6)  DEFAULT '$.path';
  DECLARE v_prop_rules    CHAR(7)  DEFAULT '$.rules';
  DECLARE v_prop_optional CHAR(10) DEFAULT '$.optional';
  DECLARE v_prop_default  CHAR(9)  DEFAULT '$.default';
  DECLARE v_prop_type     CHAR(6)  DEFAULT '$.type';
  DECLARE v_prop_nullable CHAR(10) DEFAULT '$.nullable';

  -- type constants
  DECLARE v_type_array    CHAR(5)  DEFAULT 'ARRAY';
  DECLARE v_type_boolean  CHAR(7)  DEFAULT 'BOOLEAN';
  DECLARE v_type_null     CHAR(4)  DEFAULT 'NULL';
  DECLARE v_type_object   CHAR(6)  DEFAULT 'OBJECT';
  DECLARE v_type_string   CHAR(6)  DEFAULT 'STRING';

  DECLARE i, j, n INT UNSIGNED DEFAULT 0;
  DECLARE v_optional, v_nullable BOOL;
  DECLARE v_rule, v_rules, v_subrule, v_path, v_subpath, v_item, v_opt, v_typetype, v_typetype_item, v_value_nullable JSON;
  DECLARE v_message_text, v_prop, v_type, v_expected_type, v_item_type, v_path_string TEXT;

  SET v_type = JSON_TYPE(p_rules)
  ,   v_expected_type = v_type_array
  ;
  IF v_type != v_expected_type THEN
    SET v_message_text = CONCAT('Rules parameter must be an ', v_expected_type, ' type. Found: ', v_type, '.');
    SIGNAL cond_rule_error
      SET MESSAGE_TEXT = v_message_text;
  END IF;

  _rules: WHILE i < JSON_LENGTH(p_rules) DO

    -- get a single rule from the list at the current position
    SET v_rule = JSON_EXTRACT(p_rules, CONCAT('$[', i, ']'))
    ,   i = i + 1
    ,   v_type = JSON_TYPE(v_rule)
    ,   v_expected_type = v_type_object
    ;
    IF v_type != v_expected_type THEN
      SET v_message_text = CONCAT('Rule ', i, ' must be of the ', v_expected_type, ' type. Found: ', v_type, '.');
      SIGNAL cond_rule_error
        SET MESSAGE_TEXT = v_message_text;
    END IF;

    -- get the path of the current rule
    SET v_prop = v_prop_path;
    IF NOT JSON_CONTAINS_PATH(v_rule, 'one', v_prop) THEN
      SET v_message_text = CONCAT('Rule ', i, ' must specify a ', v_prop, ' property.');
      SIGNAL cond_rule_error
        SET MESSAGE_TEXT = v_message_text;
    END IF;
    SET v_path = JSON_EXTRACT(v_rule, v_prop)
    ,   v_type = JSON_TYPE(v_path)
    ,   v_expected_type = v_type_string
    ;
    IF v_type != v_expected_type THEN
      SET v_message_text = CONCAT('Property', v_prop, ' of rule ', i, ' at path ', v_path, ' must be of the ', v_expected_type, ' type. Found: ', v_type, '.');
      SIGNAL cond_rule_error
        SET MESSAGE_TEXT = v_message_text;
    END IF;

    -- get the item identified by the current rule's path
    SET v_path_string = JSON_UNQUOTE(v_path)
    ,   v_item = JSON_EXTRACT(p_json, CONCAT('$', v_path_string))
    ;

    -- if we didn't find the item
    IF v_item IS NULL THEN
      -- check if the item might be optional
      SET v_prop = v_prop_optional;
      IF JSON_CONTAINS_PATH(v_rule, 'one', v_prop) THEN
        SET v_opt = JSON_EXTRACT(v_rule, v_prop)
        ,   v_type = JSON_TYPE(v_opt)
        ,   v_expected_type = v_type_boolean
        ;
        IF v_type != v_expected_type THEN
          SET v_message_text = CONCAT('Property ', v_prop, ' of rule ', i, ' at path ', v_path, ' must be of the ', v_expected_type, ' type. Found: ', v_type, '.');
          SIGNAL cond_rule_error
            SET MESSAGE_TEXT = v_message_text;
        END IF;
        SET v_optional = (v_opt = TRUE);
      ELSE
        SET v_optional = false;
      END IF;

      IF v_optional = TRUE THEN
        -- check if there is a default value for the optional item
        IF JSON_CONTAINS_PATH(v_rule, 'one', v_prop_default) THEN
          SET v_item = JSON_EXTRACT(v_rule, v_prop_default);
        ELSE
          -- no default value means we're done checking this item.
          ITERATE _rules;
        END IF;
      ELSE
        -- missing non-optional item.
        SET v_message_text = CONCAT('Non-optional item at path ', v_path_string, ' not found.');
        SIGNAL cond_validation_error
          SET MESSAGE_TEXT = v_message_text;
      END IF;
    END IF; -- end of optional validation

    -- establisch nullability
    SET v_item_type = JSON_TYPE(v_item)
    ,   v_prop = v_prop_nullable
    ;
    IF JSON_CONTAINS_PATH(v_rule, 'one', v_prop) THEN
      SET v_value_nullable = JSON_EXTRACT(v_rule, v_prop)
      ,   v_type = JSON_TYPE(v_value_nullable)
      ,   v_expected_type = v_type_boolean
      ;
      IF v_type != v_expected_type THEN
        SET v_message_text = CONCAT('Property ', v_prop, ' of rule ', i, ' at path ', v_path, ' must be of the ', v_expected_type, ' type. Found: ', v_type, '.');
        SIGNAL cond_rule_error
          SET MESSAGE_TEXT = v_message_text;
      END IF;
      SET v_nullable = CASE v_value_nullable
        WHEN TRUE THEN TRUE
        ELSE FALSE
      END;
    ELSE
      SET v_nullable = FALSE;
    END IF;

    -- check nullability
    IF v_nullable = FALSE AND v_item_type = v_type_null THEN
      SET v_message_text = CONCAT('Non-nullable item at path ', v_path_string, ' is null.');
      SIGNAL cond_validation_error
        SET MESSAGE_TEXT = v_message_text;
    ELSE
      -- we can't check anything about a NULL value. So move on to the next rule
      ITERATE _rules;
    END IF;

    -- check if the item is of the right type
    SET v_prop = v_prop_type;
    IF JSON_CONTAINS_PATH(v_rule, 'one', v_prop) THEN
      SET v_typetype = JSON_EXTRACT(v_rule, v_prop)
      ,   v_type = JSON_TYPE(v_typetype)
      ;
      CASE v_type
        WHEN v_type_string THEN
          -- simple type check
          IF v_item_type != v_typetype THEN
            SET v_message_text = CONCAT('Item at path ', v_path_string, ' should be of type ', v_typetype,'. Found: ', v_item_type, '.');
            SIGNAL cond_validation_error
              SET MESSAGE_TEXT = v_message_text;
          END IF;
        WHEN v_type_array THEN
          -- check item type against each item in the array
          BEGIN
            SET n = JSON_LENGTH(v_typetype)
            ,   j = 0
            ;
            _type_elements: WHILE j < n DO
              SET v_typetype_item = JSON_EXTRACT(v_typetype, CONCAT('$[', j, ']'))
              ,   v_type = JSON_TYPE(v_typetype_item)
              ,   v_expected_type = v_type_string
              ;
              IF v_type != v_expected_type THEN
                SET v_message_text = CONCAT('Item ', j, ' of property ', v_prop, ' of rule ', i, ' at path ', v_path, ' must be of the ', v_expected_type, ' type. Found: ', v_type, '.');
                SIGNAL cond_rule_error
                  SET MESSAGE_TEXT = v_message_text;
              END IF;

              IF v_typetype_item = v_item_type THEN
                LEAVE _type_elements;
              ELSE
                SET j = j + 1;
              END IF;
            END WHILE _type_elements;

            IF j = n THEN
              SET v_message_text = CONCAT('Item at path ', v_path_string, ' should have one of the types ', v_typetype, '. Found: ', v_item_type, '.');
              SIGNAL cond_validation_error
                SET MESSAGE_TEXT = v_message_text;
            END IF;
          END;
        WHEN v_type_object THEN
          -- get value from type object.
          BEGIN
            DECLARE v_typetype_object JSON;

            -- if the type object does not contain an entry for the item type, then the type if invalid.
            IF NOT JSON_CONTAINS_PATH(v_typetype, 'one', CONCAT('$.', v_item_type)) THEN
              SET v_message_text = CONCAT('Item at path ', v_path_string, ' has an invalid type. Found: ', v_item_type, '.');
              SIGNAL cond_validation_error
                SET MESSAGE_TEXT = v_message_text;
            END IF;

            -- check the type object.
            SET v_typetype_object = JSON_EXTRACT(v_typetype, CONCAT('$.', v_item_type))
            ,   v_type = JSON_TYPE(v_typetype_object)
            ;
            CASE v_type
              WHEN v_type_boolean THEN
                -- this type was explicitly excluded.
                IF v_typetype_object = FALSE THEN
                  SET v_message_text = CONCAT('Item at path ', v_path_string, ' has an invalid type. Found: ', v_item_type, '.');
                  SIGNAL cond_validation_error
                    SET MESSAGE_TEXT = v_message_text;
                END IF;
              WHEN v_type_object THEN
                -- this type has additional validation info - apply it to the current rule.
                SET v_rule = JSON_MERGE(v_rule, v_typetype_object);
              ELSE
                SET v_message_text = CONCAT('Key ', v_item_type, ' of property ', v_prop, ' of rule ', i, ' at path ', v_path, ' has the wrong type. Found: ', v_type, '.');
                SIGNAL cond_rule_error
                  SET MESSAGE_TEXT = v_message_text;
            END CASE;
          END;
        ELSE
          -- type property is of the wrong type.
          SET v_message_text = CONCAT('Property ', v_prop, ' of rule ', i, ' at path ', v_path, ' must be of type ', v_type_string , ', ', v_type_array, ', or ', v_type_object, '. Found: ', v_type, '.');
          SIGNAL cond_rule_error
            SET MESSAGE_TEXT = v_message_text;
      END CASE;
    END IF; -- end of type validation

    -- TODO: check minvalue
    -- TODO: check maxvalue
    -- TODO: check minlength
    -- TODO: check maxlength
    -- TODO: check list of values
    -- TODO: check pattern of value

    -- see if the current rule specifies sub-rules
    IF JSON_CONTAINS_PATH(v_rule, 'one', v_prop_rules) THEN
      -- get the subrules
      SET v_rules = JSON_EXTRACT(v_rule, v_prop_rules)
      ,   v_type = JSON_TYPE(v_rules)
      ,   v_expected_type = v_type_array
      ;
      IF v_type != v_expected_type THEN
        SET v_message_text = CONCAT('Rules property of rule ', i, ' must be of the ', v_expected_type, ' type. Found: ', v_type, '.');
        SIGNAL cond_rule_error
          SET MESSAGE_TEXT = v_message_text;
      END IF;

      -- get each subrule
      SET n = JSON_LENGTH(v_rules)
      ,   j = 0
      ;
      _subrules: WHILE j < n DO

        -- get one subrule
        SET v_subrule = JSON_EXTRACT(v_rules, CONCAT('$[', j, ']'))
        ,   j = j + 1
        ,   v_subpath = JSON_EXTRACT(v_subrule, v_prop_path)
        ,   v_type = JSON_TYPE(v_subpath)
        ,   v_expected_type = v_type_string
        ;
        IF v_type != v_expected_type THEN
          SET v_message_text = CONCAT('Subrule ', j, ' of rule ',  i, ' must specify a path property of the ', v_expected_type, ' type. Found: ', v_type, ' (', v_subpath, ').');
          SIGNAL cond_rule_error
            SET MESSAGE_TEXT = v_message_text;
        END IF;
        SET v_subrule = JSON_SET(v_subrule, v_prop_path, CONCAT(v_path_string, JSON_UNQUOTE(v_subpath)))
        ,   p_rules = JSON_ARRAY_INSERT(p_rules, CONCAT('$[', i + j, ']'), v_subrule)
        ;
      END WHILE _subrules;
    END IF;

  END WHILE _rules;

END;
//

delimiter ;

-- test 1: ERROR 1644 (42000): Rules parameter must be an ARRAY type. Found: OBJECT.
call p_validate_json_schema('[]', '{}');

-- test 2: Success
call p_validate_json_schema('[]', '[]');

-- test 3: ERROR 1644 (42000): Rule 1 must be of the OBJECT type. Found: INTEGER.
call p_validate_json_schema('[]', '[1]');

-- test 4: ERROR 1644 (42000): Rule 1 must specify a $.path property.
call p_validate_json_schema('[]', '[{}]');

-- test 5: ERROR 1644 (42000): Property$.path of rule 1 at path 1 must be of the STRING type. Found: INTEGER.
call p_validate_json_schema('[]', '[{
  "path": 1
}]');

-- test 6: ERROR 1644 (42000): Non-optional item at path .bla not found.
call p_validate_json_schema('[]', '[{
  "path": ".bla"
}]');

-- test 7: ERROR 1644 (42000): Property $.optional of rule 1 at path ".bla" must be of the BOOLEAN type. Found: INTEGER.
call p_validate_json_schema('[]', '[{
  "path": ".bla",
  "optional": 1
}]');

-- test 8: Success
call p_validate_json_schema('[]', '[{
  "path": ".bla",
  "optional": true
}]');

-- test 9: ERROR 1644 (42000): Non-optional item at path .bla not found.
call p_validate_json_schema('[]', '[{
  "path": ".bla",
  "optional": false
}]');

-- test 10: Success
call p_validate_json_schema('{
  "bla": 1
}', '[{
  "path": ".bla"
}]');

-- test 11: Success
call p_validate_json_schema('{
  "bla": 1
}', '[{
  "path": ".bla",
  "type": "INTEGER"
}]');

-- test 12: Success
call p_validate_json_schema('{
  "bla": 1
}', '[{
  "path": ".bla",
  "type": ["INTEGER", "DECIMAL"]
}]');

-- test 13: ERROR 1644 (42000): Item at path .bla should have one of the types ["INTEGER", "DECIMAL"]. Found: DOUBLE.
call p_validate_json_schema('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": ["INTEGER", "DECIMAL"]
}]');

-- test 14: success
call p_validate_json_schema('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": ["INTEGER", "DOUBLE"]
}]');

-- test 15: ERROR 1644 (42000): Item at path .bla has an invalid type. Found: DOUBLE.
call p_validate_json_schema('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": {"INTEGER": true, "DOUBLE": false}
}]');

-- test 16: Success
call p_validate_json_schema('{
  "bla": 1.1
}', '[{
  "path": ".bla",
  "type": {"INTEGER": false, "DOUBLE": true}
}]');

-- test 17: ERROR 1644 (42000): Non-nullable item at path .bla is null.
call p_validate_json_schema('{
  "bla": null
}', '[{
  "path": ".bla",
  "type": {"INTEGER": false, "DOUBLE": true}
}]');

-- test 18: Success
call p_validate_json_schema('{
  "bla": null
}', '[{
  "path": ".bla",
  "nullable": true,
  "type": {"INTEGER": false, "DOUBLE": true}
}]');
