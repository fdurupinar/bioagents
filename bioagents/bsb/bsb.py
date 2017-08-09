import sys
import time
import json
import uuid
import base64
import random
import select
import socket
import logging
logging.basicConfig(format='%(levelname)s: %(name)s - %(message)s',
                    level=logging.INFO)
logger = logging.getLogger('BSB')
from socketIO_client import SocketIO

from indra.statements import stmts_from_json
from indra.assemblers import SBGNAssembler

from kqml import *


class BSB(object):
    def __init__(self,  bob_port=6200, sbgnviz_port=3000):
        self.user_name = 'BOB'

        self.bob_port = bob_port
        #  self.sbgnviz_port = sbgnviz_port

        # Startup sequences
        self.bob_startup()
        #self.sbgn_startup()
        msg = '(tell :content (start-conversation))'
        self.socket_b.sendall(msg)

    def start(self):
        logger.info('Starting...')
        # Wait for things to happen

        while True:
            try:
                data, addr = self.socket_b.recvfrom(1000000)
                if data:
                    parts = data.split('\n')
                    for part in parts:
                        if part:
                            self.on_bob_message(part)
            except : #funda (KeyboardInterrupt):
                break



    def bob_startup(self):
        logger.info('Initializing Bob connection...')
        self.bob_uttnum = 1
        self.socket_b = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket_b.connect(('localhost', self.bob_port))
        msg = '(register :name bsb)'
        self.socket_b.sendall(msg)
        msg = '(subscribe :content (tell &key :content (spoken . *)))'
        self.socket_b.sendall(msg)
        msg = '(subscribe :content (tell &key :content (display-model . *)))'
        self.socket_b.sendall(msg)
        msg = '(subscribe :content (tell &key :content (display-image . *)))'
        self.socket_b.sendall(msg)
        msg = '(tell :content (module-status ready))'
        self.socket_b.sendall(msg)





    def send_to_bob(self, msg):
        try:
            self.socket_b.sendall(msg)
        except:
            print("Socket error")




    def on_bob_message(self, data):
        logger.debug('data: ' + data)
        # Check what kind of message it is
        kl = KQMLPerformative.from_string(data)
        head = kl.head()
        content = kl.get('content')
        if head == 'tell' and content.head().lower() == 'display-model':
            parts = data.split('\n')
            if len(parts) > 1:
                logger.error('!!!!!!!!!!!!\nMessage with multiple parts\n ' +
                             '!!!!!!!!!!!')
                logger.error(parts)
        logger.info('Got message with head: %s' % head)
        logger.info('Got message with content: %s' % content)
        if not content:
            return
        if content.head().lower() == 'spoken':
            spoken_phrase = get_spoken_phrase(content)
            self.bob_to_sbgn_say(spoken_phrase)
        elif content.head().lower() == 'display-model':
            stmts_json = content.gets('model')
            stmts = decode_indra_stmts(stmts_json)
            self.bob_to_sbgn_display(stmts)
        

    def bob_to_sbgn_say(self, spoken_phrase):
        msg = KQMLPerformative('tell')
        content = KQMLList('spoken')
        content.sets('what',spoken_phrase)
        msg.set('content', content)

    def bob_to_sbgn_display(self, stmts):
        sa = SBGNAssembler()
        sa.add_statements(stmts)
        sbgn_content = sa.make_model()


        msg = KQMLPerformative('request')
        content = KQMLList('display-sbgn')
        content.sets('graph', sbgn_content)
        msg.set('content', content)
        self.socket_b.sendall(str(msg))





def decode_indra_stmts(stmts_json_str):
    stmts_json = json.loads(stmts_json_str)
    stmts = stmts_from_json(stmts_json)
    return stmts

def print_json(js):
    s = json.dumps(js, indent=1)
    print(s)

def get_spoken_phrase(content):
    say_what = content.gets('what')
    return say_what


if __name__ == '__main__':
    bsb = BSB()
    bsb.start()