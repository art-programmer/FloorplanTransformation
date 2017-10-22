import os
import sys
import subprocess
import re
import math
import signal


################## generate hosts list  #####################
prefix = 'visiongpu'
suffix = 'bill'
ind_list = range(1, 15)     # range(14)?
ind_high_priority_list = [2,4,5,12,13,14]
ind_low_priority_list = [ind for ind in ind_list if ind not in ind_high_priority_list]
hosts_hp = []
for ind in ind_high_priority_list:
    host = prefix + "{:0>2d}".format(ind)
    if ind > 11:
        host += suffix
    hosts_hp.append(host)

hosts_lp = []
for ind in ind_low_priority_list:
    host = prefix + "{:0>2d}".format(ind)
    if ind > 11:
        host += suffix
    hosts_lp.append(host)


users = ['ckzhang','jiajunwu']
timeout_limit = 4 # sec

####################### util functions ########################

#### Timeout Control ###
class TimeoutError(Exception):
    pass

class timeout:
    def __init__(self, seconds=10, error_message='Timeout'):
        self.seconds = seconds
        self.error_message = error_message
    def handle_timeout(self, signum, frame):
        raise TimeoutError(self.error_message)
    def __enter__(self):
        signal.signal(signal.SIGALRM, self.handle_timeout)
        signal.alarm(self.seconds)
    def __exit__(self, type, value, traceback):
        signal.alarm(0)

#### Color output ####
class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

###################### Basic functions #######################

def ssh_nvidia(host):
    """ retrieve nvidia-smi data from given host"""
    print "checking "+host+'\t',
    try:
        with timeout(seconds=timeout_limit):
            result = subprocess.check_output('ssh '+host+' "nvidia-smi;exit"', shell=True)
            print "done"
            return result
    except TimeoutError, exc:
        print "timeout"
        return ""

def parse_nvidia(output, users=None):
    """
    @param output nvidia-smi output
    @return list of tuples of (occupied mem, total mem, util percentile, user memory usage), one for each gpu
    """
    if output == "":
        return [(-1, -1, -1, 0)]
    lines = output.strip().split('\n')
    gpu_counter = 0
    result = []
    for line in lines:
        # gpu line
        if len(re.findall('[0-9]+MiB\s*/\s*[0-9]+MiB', line)) > 0:
            data = re.findall('[0-9]+MiB\s*/\s*[0-9]+MiB\s*\|\s*[0-9]+%', line)[0]
            occupied = int(re.findall('[0-9]+', data)[0])
            total =  int(re.findall('[0-9]+',data)[1])
            util = int(re.findall('[0-9]+',data)[2])
            result.append( (occupied, total, util))

            gpu_counter += 1

    usage = [0]*gpu_counter
    if users != None:
        user_pattern = "|".join(users)
        for line in lines:
            # find user's usage
            if len(re.findall(user_pattern, line)) > 0:
                gpu_id = int(re.findall('[0-9]+',line)[0])
                mem = int(re.findall('[0-9]+MiB',line)[-1][:-3])
                usage[gpu_id] += mem
    for gpu_id in xrange(len(usage)):
        result[gpu_id] = result[gpu_id] + tuple([usage[gpu_id]])

    return result

def collect_gpu_data(hosts, users=None):
    """ given list of hosts, return map of hostname to gpu usage list defined by parse_nvidia"""
    result = dict()
    for host in hosts:
        result[host] = parse_nvidia(ssh_nvidia(host), users)
    return result

def sort_gpu(hosts_lp, hosts_hp=[], util_thres=10, mem_thres=1000):
    """
    Given lists of hosts and threshold, return number of available hosts
    """
    map_hp = collect_gpu_data(hosts_hp, users)
    map_lp = collect_gpu_data(hosts_lp, users)
    print "All GPU checked. "
    print "Sorting..."
    map_merge = map_hp.copy()
    map_merge.update(map_lp)
    map_avail = dict()
    for host in map_merge:
        usable = 0
        mem = 0
        for gpu in map_merge[host]:
            if gpu[0] < 0:  # Timeout
                mem = -1
                usable = -1
            elif gpu[0] < mem_thres and gpu[2] < util_thres:
                mem += (gpu[1]-gpu[0])/1000             # available memory
                usable += 1                             # available gpu
        map_avail[host] = (usable, mem)

    hosts_lp_sorted = sorted(hosts_lp, key=lambda host: map_avail[host], reverse=True)
    hosts_hp_sorted = sorted(hosts_hp, key=lambda host: map_avail[host], reverse=True)

    return hosts_hp_sorted + hosts_lp_sorted, map_merge, map_avail

def display(hosts, resources, map_avail):
    """ Given list of hosts, map to resources and map to available gpu numbers and total memories, display them in order
        Display format: hostname, available # gpu, total mem of available gpu, user used mem, then mem usage of each gpu is displayed.
    """
    print bcolors.HEADER + "hostname\t#gpus\tava mem\tuser mem gpu-specific mem usage" + bcolors.ENDC

    for host in hosts:
        if resources[host][0][0] == -1: # Timeout
            out = host+'\t'+"Timeout"
        else:
            out = host+'\t'+ str(map_avail[host][0])+'\t'+ str(map_avail[host][1])+'G'+'\t'+ str(int(math.ceil(sum([gpu[3] for gpu in resources[host]])/1000.)))+'G\t'
            for gpu in resources[host]:
                out += str(gpu[0]).rjust(6)+'/'+str(gpu[1]).rjust(6)+'\t'

        if map_avail[host][0] == 4:
            print bcolors.OKGREEN + out + bcolors.ENDC
        elif sum([gpu[3] for gpu in resources[host]]) > 0:
            print bcolors.OKBLUE + out + bcolors.ENDC
        elif resources[host][0][0] == -1: # Timeout
            print bcolors.FAIL + out + bcolors.ENDC
        else:
            print out

## test ##

#hosts_sorted, resources, map_avail = sort_gpu([], hosts_hp)
hosts_sorted, resources, map_avail = sort_gpu(hosts_lp, hosts_hp)
display(hosts_sorted, resources, map_avail)




