import importlib.machinery, importlib.util, unittest
from pathlib import Path
from unittest.mock import patch
loader=importlib.machinery.SourceFileLoader('ambient',str(Path(__file__).resolve().parents[1] / 'bin' / 'ambient-light'))
spec=importlib.util.spec_from_loader(loader.name,loader); a=importlib.util.module_from_spec(spec); loader.exec_module(a)
class AmbientTests(unittest.TestCase):
 def test_categories(self):
  for value,mode in [(0,'high'),(60,'low'),(220,'off')]:self.assertEqual(a.classify(value)[1],mode)
 def test_hysteresis(self):
  for value,old,expected in [(40,'high','high'),(44,'high','low'),(30,'low','low'),(26,'low','high'),(110,'low','low'),(114,'low','off'),(100,'off','off'),(96,'off','low')]:self.assertEqual(a.classify(value,mode=old)[1],expected)
 def test_smoothing(self):
  self.assertAlmostEqual(a.classify(100,previous=0)[0],35)
 def test_invalid_thresholds(self):
  for d,b in [(105,35),(35,40),(-1,105),(35,300),(float('nan'),105)]:
   with self.assertRaises(ValueError):a.classify(60,dark=d,bright=b)
 def test_busy_no_controls_changed(self):
  with patch.object(a.Path,'exists',return_value=True),patch.object(a.subprocess,'run') as proc,patch.object(a,'run') as command:
   proc.return_value.returncode=0
   with self.assertRaisesRegex(RuntimeError,'busy'):a.capture('/dev/test')
   command.assert_not_called()
 def test_restore_after_capture_failure(self):
  calls=[]; controls={'auto_exposure':3,'exposure_time_absolute':200,'exposure_dynamic_framerate':1}
  def command(args,timeout=3):
   calls.append(args)
   if args[0]=='ffmpeg':raise RuntimeError('Capture failed')
   option=args[-1]
   if option.startswith('--get-ctrl='):
    key=option.split('=',1)[1];return (key+': '+str(controls[key])).encode()
   key,value=option.split('=',1)[1].split('=');controls[key]=int(value);return b''
  with patch.object(a.Path,'exists',return_value=True),patch.object(a.subprocess,'run') as proc,patch.object(a,'run',side_effect=command):
   proc.return_value.returncode=1
   with self.assertRaisesRegex(RuntimeError,'Capture failed'):a.capture('/dev/test')
  self.assertEqual(controls,{'auto_exposure':3,'exposure_time_absolute':200,'exposure_dynamic_framerate':1})
if __name__=='__main__':unittest.main()
