import unittest
from uuid import uuid4
from fios_agent.protocol import parse_command,parse_event,encode_frame,FrameDecoder,ProtocolError


class WebProtocolTests(unittest.TestCase):
    def test_v2_status_null_roundtrip_and_strict_fields(self):
        status={'phase':'searching','outcome':'pending','reason':None,'tool_attempted':True}
        event={'v':2,'type':'search_status','run_id':str(uuid4()),'status':status}
        parsed=parse_event(event)
        self.assertEqual(list(FrameDecoder(1048576).feed(encode_frame(parsed)))[0],event)
        for patch in [{'reason':'raw error'},{'tool_attempted':1},{'extra':'query'},{'phase':'finished'}]:
            with self.assertRaises(ProtocolError): parse_event({**event,'status':{**status,**patch}})
        with self.assertRaises(ProtocolError): parse_event({**event,'v':1})

    def test_missing_provenance_omits_tool_but_explicit_null_is_invalid(self):
        value={'v':2,'type':'run','run_id':str(uuid4()),'model':'exact/model@peer','context':[{'role':'user','content':'Python'}]}
        self.assertIsNone(parse_command(value).search_input)
        with self.assertRaises(ProtocolError): parse_command({**value,'search_input':None})

    def test_reset_is_fixed_and_correlated(self):
        value={'v':2,'type':'answer_reset','run_id':str(uuid4()),'reason':'tool_requested'}
        parse_event(value)
        for patch in [{'reason':'raw arguments'},{'run_id':'bad'},{'extra':'private'}]:
            with self.assertRaises(ProtocolError): parse_event({**value,**patch})
