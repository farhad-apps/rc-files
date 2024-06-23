const http = require("http");
const { exec } = require("child_process");
const os = require("os");
const fs = require("fs");
const process = require("process");
const { Buffer } = require("buffer");
const path = require('path');

const API_URL = "{rapiUrl}";
const API_TOKEN = "{rapiToken}";

var settings = {
  calc_traffic: 1,
};

const runCmd = (command) => {
  return new Promise((resolve, reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error) {
        resolve({ stdout: "", stderr: "" });
      }
      if (stdout) {
        stdout = stdout.trim();
      }
      resolve({ stdout, stderr });
    });
  });
};

const helpers = {
  checkServiceExists: async (serviceName) => {
    const command = `systemctl list-units --type=service | grep "${serviceName}";`;
    const { stdout } = await runCmd(command);
    if (stdout && stdout.trim() !== "") {
      return true;
    }
    return false;
  },
  checkInstalledSSH: async () => {
    const filePath = `/lib/security/rocket_ssh_auth.so`;
    if (fs.existsSync(filePath)) {
      return true;
    }
    return false;
  },
  checkInstalleOvpn: async () => {
    const filePath = `/etc/openvpn/server.conf`;
    if (fs.existsSync(filePath)) {
      return true;
    }
    return false;
  },
  checkInstalleV2ray: async () => {
    const filePath = `/var/rocket-ssh/xray/xray`;
    if (fs.existsSync(filePath)) {
      return true;
    }
    return false;
  },
  snaitizeCmdOut: (output) => {
    output = output.replaceAll("\n", output);
    output = output.trim(output);
    return output;
  },
  calculateCPUsage: async () => {
    const { stdout } = await runCmd('top -bn1 | grep "%Cpu(s)"');
    const cpuUsage = parseFloat(stdout.split(",")[0].split(":")[1].trim());
    return cpuUsage;
  },
  getHDDInfo: async () => {
    const rootPath = "/";
    const result = {
      total: 0,
      used: 0,
      free: 0,
      precent: 0,
    };

    const { stdout } = await runCmd(`df -h ${rootPath}`);
    if (stdout) {
      const outputLines = stdout.split("\n");
      const [_, total, used, free, precent] = outputLines[1].split(/\s+/);
      result.total = total;
      result.used = used;
      result.free = free;
      result.precent = precent;
    }

    return result;
  },
  sysData: async () => {
    const cpus = os.cpus();
    const uptime = os.uptime();
    const loadavg = os.loadavg();
    const freemem = os.freemem();
    const totalmem = os.totalmem();

    //
    const cpuUsage = await helpers.calculateCPUsage();
    const usedMemory = totalmem - freemem;

    //
    const totalDownload = await helpers.getDownloadUsage();
    const totalUpload = await helpers.getUploadUsage();
    const appStatus = await helpers.getRocketAppStatus();

    const v2rayService = await helpers.isServiceRunning("rsxray");
    const v2rayInstalled = await helpers.checkInstalleV2ray();
    const openvpnService = await helpers.isServiceRunning("openvpn");
    const openvpnInstalled = await helpers.checkInstalleOvpn("openvpn");
    const sshInstalled = await helpers.checkInstalledSSH();

    const traffic = {
      download: totalDownload,
      upload: totalUpload,
      total: totalDownload + totalUpload,
    };

    const cpuInfo = {
      details: cpus,
      cores: cpus.length,
      uptime: uptime,
      loadavg: loadavg,
      usage: cpuUsage,
    };

    const memeoryInfo = {
      total: totalmem,
      free: freemem,
      used: usedMemory,
    };

    const hddInfo = await helpers.getHDDInfo();

    const result = {
      cpu: cpuInfo,
      memeory: memeoryInfo,
      hdd: hddInfo,
      traffic,
      app_status: appStatus,
      protocols: {
        v2ray: {
          is_installed: v2rayInstalled,
          is_running: v2rayService,
        },
        openvpn: {
          is_installed: openvpnInstalled,
          is_running: openvpnService,
        },
        ssh: sshInstalled,
      },
    };

    if (settings.enabled_ssh) {
      const { stdout } = await runCmd("getent group rocketSSH");
      var sshUsers = [];
      if (stdout) {
        sshUsers = stdout.split(",");
      }
      result.ssh_users = sshUsers;
    }

    return result;
  },
  createUser: async (username, password, uuid) => {
    if (settings.enabled_ssh) {
      const addUserCommand = `sudo adduser ${username} --force-badname --shell /usr/sbin/nologin &`;
      const setPasswordCommand = `sudo passwd ${username} <<!\n${password}\n${password}\n!`;
      const fullCommand = `${addUserCommand}\nwait\n${setPasswordCommand}`;
      await runCmd(fullCommand);

      await runCmd(`sudo adduser ${username} rocketSSH`);
    }

    if (settings.enabled_v2ray && uuid) {
      await helpers.v2rayActionUser("create", username, uuid)
    }
  },
  killUser: async (username) => {
    await runCmd(`sudo killall -u ${username}`);
    await runCmd(`sudo pkill -u ${username}`);
    await runCmd(`sudo timeout 10 pkill -u ${username}`);
    await runCmd(`sudo timeout 10 killall -u ${username}`);
  },
  removeUser: async (username) => {
    if (settings.enabled_ssh) {
      const cmd = `sudo userdel -r ${username}`;
      await runCmd(cmd);
    }
    if (settings.enabled_v2ray) {
      await helpers.v2rayActionUser("delete", username)
    }
  },
  getUsersList: async () => {
    const { stdout } = await runCmd("ls /home");
    let users = [];
    if (stdout) {
      const outputArray = stdout.split(/\r\n|\n|\r/);
      const invalidUsers = ["videocall", "ocean"];
      users = outputArray.filter((user) => !invalidUsers.includes(user)).map((user) => user.trim());
    }
    return users;
  },
  isNumeric: (value) => {
    return /^\d+$/.test(value);
  },
  getDownloadUsage: async () => {
    let download = 0;

    const { stdout } = await runCmd("netstat -e -n -i | grep 'RX packets' | grep -v 'RX packets 0' | grep -v ' B)' | awk '{print $5}'");
    if (stdout) {
      const outputArray = stdout.split(/\r\n|\n|\r/);
      outputArray.forEach((value) => {
        download += parseInt(value);
      });
    }

    return download;
  },
  getUploadUsage: async () => {
    let upload = 0;
    const { stdout } = await runCmd("netstat -e -n -i | grep 'TX packets' | grep -v 'TX packets 0' | grep -v ' B)' | awk '{print $5}'");
    if (stdout) {
      const outputArray = stdout.split(/\r\n|\n|\r/);
      outputArray.forEach((value) => {
        upload += parseInt(value);
      });
    }
    return upload;
  },
  getRocketAppStatus: async () => {
    const cmd = `sudo supervisorctl status rocketApp | awk '{print  $2}'`;
    const { stdout } = await runCmd(cmd);
    return stdout;
  },
  isServiceRunning: async (service) => {
    const cmd = `systemctl --type=service --state=running | grep ${service}`;
    const { stdout } = await runCmd(cmd);
    if (stdout && stdout.trim()) {
      return true
    }
    return false;
  },
  v2rayHasUer: (clients, userEmail) => {
    var find = false;
    if (clients && clients.length) {
      for (var client of clients) {
        const email = client["email"];
        if (userEmail === email) {
          find = true;
        }
      }
    }
    return find;
  },
  v2rayActionUser: async (action, username, uuid) => {
    const vmessFilePath = "/var/rocket-ssh/xray/conf/02_vmess_tcp.json";
    const vlessFilePath = "/var/rocket-ssh/xray/conf/01_vless_tcp.json";
    const userEmail = `${username}@rocket-ssh.com`

    await helpers.v2rayActionUserFile(vmessFilePath, action, uuid, userEmail);
    await helpers.v2rayActionUserFile(vlessFilePath, action, uuid, userEmail);
  },
  v2rayActionUserFile: (filePath, action, uuid, userEmail) => {
    return new Promise((resolve, reject) => {
      fs.readFile(filePath, 'utf8', (err, data) => {
        if (err) {
          reject(err);
          return;
        }
        const configs = JSON.parse(data);
        const lastClients = configs.inbounds[0].settings.clients;

        if (action === "create") {
          const findUser = helpers.v2rayHasUer(lastClients, userEmail);
          if (!findUser) {
            lastClients.push({
              id: uuid,
              level: 0,
              email: userEmail,
            });
          }
        } else if (action === "delete") {
          const updatedClients = lastClients.filter((client) => client.email !== userEmail);
          configs.inbounds[0].settings.clients = updatedClients;
        }

        const modifiedData = JSON.stringify(configs, null, 2);
        fs.writeFile(filePath, modifiedData, 'utf8', (err) => {
          if (err) {
            reject(err);
            return;
          }
          resolve();
        });
      });
    });
  }
};

const apiActions = {
  createUser: async (pdata) => {
    const { username, password, uuid } = pdata;
    await helpers.createUser(username, password, uuid);
  },
  removeUser: async (pdata) => {
    const { username } = pdata;
    await helpers.killUser(username);
    await helpers.removeUser(username);
  },
  killUser: async (pdata) => {
    const { username } = pdata;
    await helpers.killUser(username);
  },
  updateUser: async (pdata) => {
    const { username, password } = pdata;
    await helpers.killUser(username);
    await helpers.removeUser(username);
    await helpers.createUser(username, password);
  },
  killUserByPid: async (pdata) => {
    const { pid, user_ip, protocol } = pdata;
    if (protocol === 'ssh' && settings.enabled_ssh) {
      const command = `pstree -p ${pid} | awk -F\"[()]\" '/sshd/ {print $4}'`;
      const { stdout } = await runCmd(command);
      if (stdout) {
        const procId = stdout;
        await runCmd(`sudo kill -9 ${procId}`);
        await runCmd(`sudo timeout 10 kill -9 ${procId}`);
      }
    } else if (protocol === "openvpn" && settings.enabled_openvpn) {
      const value = `${user_ip}:${pid}`
      const command = `echo "kill ${value}" | telnet localhost 7505`;
      await runCmd(command);
    } else {

    }
  },
};

const sendToApi = (endpoint, pdata = false) => {
  return new Promise((resolve, reject) => {
    const urlPath = `/sapi/${endpoint}?token=${API_TOKEN}`;
    const baseUrlPath = new URL(API_URL);
    const baseUrl = baseUrlPath.host;

    const options = {
      hostname: baseUrl,
      port: 80,
      path: urlPath,
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    };
    if (pdata) {
      options.method = "POST";
    }

    const req = http.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => {
        data += chunk;
      });
      res.on("end", () => {
        resolve(data);
      });
    });

    req.on("error", (error) => {
      reject(error);
    });

    if (pdata) {
      req.write(pdata);
    }

    req.end();
  });
};

const LoopMethods = {
  doStart: async () => {
    LoopMethods.getSettings();
    LoopMethods.sendSshTraffic();
    LoopMethods.sendOvpnTraffic();
    LoopMethods.sendV2rayTraffic();
    LoopMethods.resetSshSerivces();
    LoopMethods.removeAuthLog();
    LoopMethods.sendUsersAuthPids();

    console.log("start loop methods");
  },
  getSettings: async () => {
    sendToApi("settings")
      .then((result) => {
        result = JSON.parse(result);
        settings = { ...result };
        setTimeout(LoopMethods.getSettings, 10 * 60 * 1000);
      })
      .catch((err) => {
        setTimeout(LoopMethods.getSettings, 10 * 60 * 1000);
      });
  },
  sendSshTraffic: async () => {
    if (settings.calc_traffic && settings.enabled_ssh) {
      const command = "sudo nethogs -j -v3 -c6";
      runCmd(command)
        .then((res) => {
          runCmd(`sudo pkill nethogs`);
          const { stdout } = res;

          if (stdout) {
            const base64Encoded = Buffer.from(stdout).toString("base64");
            const pdata = JSON.stringify({ data: base64Encoded });
            sendToApi("ssh/utraffic", pdata);
          }
          runCmd("pgrep nethogs").then((result) => {
            const { stdout } = result;
            if (stdout) {
              runCmd(`sudo kill -9 ${stdout}`);
              runCmd("sudo killall -9 nethogs");
            }
          });
          setTimeout(LoopMethods.sendSshTraffic, 5000);
        })
        .catch((err) => {
          setTimeout(LoopMethods.sendSshTraffic, 5000);
        });
    } else {
      setTimeout(LoopMethods.sendSshTraffic, 5000);
    }
  },
  sendOvpnTraffic: async () => {
    if (settings.calc_traffic && settings.enabled_openvpn) {
      const command = "cat /etc/openvpn/status.log";
      runCmd(command).then(res => {
        const { stdout } = res;
        if (stdout) {
          const base64Encoded = Buffer.from(stdout).toString("base64");
          const pdata = JSON.stringify({ data: base64Encoded });
          sendToApi("ovpn/utraffic", pdata);
        }
        setTimeout(LoopMethods.sendOvpnTraffic, 10000);
      }).catch((err) => {
        setTimeout(LoopMethods.sendOvpnTraffic, 10000);
      });
    } else {
      setTimeout(LoopMethods.sendOvpnTraffic, 10000);
    }
  },
  sendV2rayTraffic: async () => {
    if (settings.calc_traffic && settings.enabled_v2ray) {
      const command = `/var/rocket-ssh/xray/xray api statsquery --server="127.0.0.1:65432"`;
      runCmd(command).then(res => {
        const { stdout } = res;
        if (stdout) {
          const base64Encoded = Buffer.from(stdout).toString("base64");
          const pdata = JSON.stringify({ data: base64Encoded });
          sendToApi("v2ray/utraffic", pdata);
          const resetCommand = `${command} --reset : true`;
          runCmd(resetCommand)
        }
        setTimeout(LoopMethods.sendV2rayTraffic, 10000);
      }).catch((err) => {
        setTimeout(LoopMethods.sendV2rayTraffic, 10000);
      });
    } else {
      setTimeout(LoopMethods.sendV2rayTraffic, 10000);
    }
  },
  resetSshSerivces: async () => {
    runCmd("sudo service ssh restart");
    runCmd("sudo service sshd restart");
    setTimeout(LoopMethods.resetSshSerivces, 1800 * 1000);
  },
  removeAuthLog: async () => {
    runCmd("sudo truncate -s 0 /var/log/auth.log");
    runCmd("sudo truncate -s 0 /etc/openvpn/openvpn.log");
    setTimeout(LoopMethods.removeAuthLog, 3600 * 1000);
  },
  sendUsersAuthPids: async () => {
    runCmd(`ps aux | grep priv | awk '{print $2}'`)
      .then((result) => {
        const { stdout } = result;
        if (stdout) {
          const base64Encoded = Buffer.from(stdout).toString("base64");
          const pdata = JSON.stringify({ pid_list: base64Encoded });
          sendToApi("ssh/uactivities", pdata);
        }
        setTimeout(LoopMethods.sendUsersAuthPids, 10 * 1000);
      })
      .catch((err) => {
        setTimeout(LoopMethods.sendUsersAuthPids, 10 * 1000);
      });
  },
};

const hanldeApiAction = async (pdata) => {
  try {
    const action = pdata.action;
    if (action === "create-users") {
      const { users } = pdata;
      if (users && Array.isArray(users)) {
        for (var user of users) {
          await apiActions.createUser(user);
        }
        if (settings.enabled_v2ray) {
          runCmd("systemctl restart rsxray")
        }
      }
    } else if (action === "remove-users") {
      const { users } = pdata;
      if (users && Array.isArray(users)) {
        for (var user of users) {
          await apiActions.removeUser(user);
        }

        if (settings.enabled_v2ray) {
          runCmd("systemctl restart rsxray")
        }
      }
    } else if (action === "sys-data") {
      return await helpers.sysData();

    } else if (action === "kill-upid") {
      apiActions.killUserByPid(pdata);

    } else if (action === "update-users") {
      const { users } = pdata;
      if (users && Array.isArray(users)) {
        for (var user of users) {
          await apiActions.updateUser(user);
        }
      }
    } else if (action === "kill-users") {
      const { users } = pdata;
      if (users && Array.isArray(users)) {
        for (var user of users) {
          await apiActions.killUser(user);
        }
      }
    } else if (action === "ovpn-client-conf") {
      const command = "cat /etc/openvpn/myuser.txt";
      const { stdout } = await runCmd(command)
      return {
        conf: stdout
      }

    } else if (action === "exec-command") {
      const { command } = pdata;
      const { stdout } = await runCmd(command)
      return {
        result: stdout
      }
    }
  } catch (err) {
    console.log("error hanldeApiAction", err);
  }
};

const server = http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  var urlPath = req.url;
  var sendMethod = req.method;

  if (sendMethod === "POST") {
    const authToken = req.headers["x-auth"];

    if (authToken !== "p5c23cb5nopit1ak3g6nbfqv84hewl") {
      res.writeHead(401, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Unauthorized" }));
      return;
    }

    if (urlPath === "/") {
      var pdata = "";
      const readBody = () =>
        new Promise((resolve) => {
          req.on("data", (chunk) => {
            pdata += chunk.toString();
          });

          req.on("end", () => {
            resolve();
          });
        });
      await readBody();

      //handle actions
      if (pdata) {
        pdata = JSON.parse(pdata);
        try {
          if (pdata.action === "download-file") {
            const { file_path } = pdata;
            const fileName = path.basename(file_path);
            if (fs.existsSync(file_path)) {
              const fileStream = fs.createReadStream(file_path);
              res.setHeader('Content-Type', 'application/octet-stream');
              res.setHeader('Content-Disposition', `attachment; filename=${fileName}`);
              fileStream.pipe(res);
              return res;
            }

          } else {
            var result = await hanldeApiAction(pdata);
            res.writeHead(200, { "Content-Type": "application/json" });
            if (!result) {
              result = { status: "success" };
            }
            return res.end(JSON.stringify(result));
          }
        } catch (err) {
          console.log("error", err)
        }
      }

      res.writeHead(200, { "Content-Type": "application/json" });
      return res.end("");
    }
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  return res.end("Not Found");
});

process.on("unhandledRejection", (error) => {
  console.log("unhandledRejection: " + JSON.stringify(error.stack));
});

process.on("uncaughtException", (error) => {
  console.log("uncaughtException: " + JSON.stringify(error.stack));
});

server.listen(3000, "localhost", () => {
  console.log("Listening for request");

  LoopMethods.doStart();
});
