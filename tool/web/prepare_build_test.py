import base64
import unittest
from prepare_build import public_config, PROJECT

def token(**claims):
    import json
    return 'eyJ.' + base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip('=') + '.fixture'

class PublicBuildTest(unittest.TestCase):
    def test_strips_all_nonpublic_configuration(self):
        key = token(role='anon', ref='hkjpojobdbbtjkhaudki')
        self.assertEqual(public_config({'SUPABASE_URL':PROJECT,'SUPABASE_ANON_KEY':key,'DEV_LOGIN_PASSWORDS':'private','SERVICE_ROLE_KEY':'private'}), {'SUPABASE_URL':PROJECT,'SUPABASE_ANON_KEY':key})
    def test_rejects_service_or_wrong_project(self):
        for role, ref in [('service_role','hkjpojobdbbtjkhaudki'),('anon','another-project')]:
            with self.assertRaises(ValueError): public_config({'SUPABASE_URL':PROJECT,'SUPABASE_ANON_KEY':token(role=role,ref=ref)})
        with self.assertRaises(ValueError): public_config({'SUPABASE_URL':'https://example.com','SUPABASE_ANON_KEY':'x'})

if __name__ == '__main__': unittest.main()
