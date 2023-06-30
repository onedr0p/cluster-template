#!/usr/bin/env zx
import { parseArgs } from 'node:util';
import { createLogger, format, transports } from 'winston';
import { parse } from 'yaml'
import { readFile, writeFile, access, rm, appendFile } from 'fs/promises';
import * as yaml from 'yaml';
import * as crypto from 'node:crypto';

//#region Script Config
const testing = false;
const requiredPackages = ['age', 'flux', 'git', 'gitops', 'ipcalc', 'jq', 'pip3', 'sops', 'ssh', 'task', 'yq'];
const tmpl = path.join(__dirname, 'tmpl');
const ageKeyFile = '~/.config/sops/age/keys.txt';
const defaultHostPrefix = 'k8s';
//#endregion

//#region Main
const logger = createLogger({
    level: 'info',
    format: format.combine(
        format.colorize(),
        format.simple(),
        format.printf(({ level, message }) => {
            return (level.indexOf('info') > -1 ? message : `${level}: ${message}`);
        })
    ),
    transports: [
        new transports.Console(),
        new transports.File({ filename: 'configure.log', options: { flags: 'w' } }),
    ],
});

async function main() {
    const {
        values: { verify, configure, debug },
    } = parseArgs({
        options: {
            debug: {
                type: 'boolean',
                short: 'd',
                default: false
            },
            verify: {
                type: 'boolean',
                short: 'v',
                default: false
            },
            configure: {
                type: 'boolean',
                short: 'c',
                default: false
            },
        },
        allowPositionals: true,
    });

    logger.info('     ________                 ________           __                ______                     __      __      ');
    logger.info('    / ____/ /_  ___  __      / ____/ /_  _______/ /____  _____    /_  __/__  ____ ___  ____  / /___ _/ /____  ');
    logger.info('   / /_  / / / / / |/_/_____/ /   / / / / / ___/ __/ _ \\/ ___/_____/ / / _ \\/ __ `__ \\/ __ \\/ / __ `/ __/ _ \\ ');
    logger.info('  / __/ / / /_/ />  </_____/ /___/ / /_/ (__  ) /_/  __/ /  /_____/ / /  __/ / / / / / /_/ / / /_/ / /_/  __/ ');
    logger.info(' /_/   /_/\\__,_/_/|_|      \\____/_/\\__,_/____/\\__/\\___/_/        /_/  \\___/_/ /_/ /_/ .___/_/\\__,_/\\__/\\___/  ');
    logger.info(`                                                                                   /_/ ${chalk.green('onedr0p rocks')}!           `);

    if (debug) {
        logger.level = 'debug';
        logger.debug('Debug mode enabled\n');
    }

    if (verify) verifyConfigure();
    else if (configure) runConfigure();
    else {
        logger.info('Usage: configure.mjs [options]');
        logger.info('Options:');
        logger.info('  -d, --debug      Enable debug mode');
        logger.info('  -v, --verify     Verify the configuration');
        logger.info('  -c, --configure  Install configuration');
    }
}

within(async() => {
    await main();
});
//#endregion

//#region Schema
class BaseConfig {
    validate() {
        this.required && this.required.forEach(required => {
            if (!this[required]) throw new Error(`${this.constructor.name}: ${required} is required`);
        });
        this.patterns && Object.keys(this.patterns).forEach((key) => {
            try {
                const result = this.patterns[key].test(this[key]);
                if (!result) throw new Error();
            } catch (e) {
                logger.debug(e.message);
                throw new Error(`${this.constructor.name}: ${key} has an invalid format`);
            }
        });
    }

    toYaml() {
        let clone = Object.assign({}, this);
        this._filterPatternsAndRequiredProperties(clone);
        return yaml.stringify(clone);
    }

    _filterPatternsAndRequiredProperties(clone) {
        Object.keys(clone).forEach(key => {
            if (key == 'required' || key == 'patterns') delete clone[key];
            else if (typeof clone[key] == 'object') this._filterPatternsAndRequiredProperties(clone[key]);
        });
    }

}

class Config extends BaseConfig {
    required = ['email', 'timezone', 'ageKey', 'network', 'github', 'cloudflare', 'nodes'];
    patterns = {
        email: /^.+@.+\..+$/,
        ageKey: /^age.*/,
        timezone: /^.+\/.+$/,
    };

    constructor(config) {
        super();
        this.email = config.email;
        this.timezone = config.timezone;
        this.ageKey = config.ageKey;
        this.apps = new ConfigApps(config.apps);
        this.network = new ConfigNetwork(config.network);
        this.github = new ConfigGithub(config.github);
        this.cloudflare = new ConfigCloudflare(config.cloudflare);
        this.nodes = config.nodes.map((node, index) => new ConfigNode(node, index));
    }

    validate() {
        super.validate();
        this.apps.validate();
        this.network.validate();
        this.github.validate();
        this.cloudflare.validate();
        this.nodes.forEach(node => node.validate());
    }
}

class ConfigApps extends BaseConfig {
    required = ['weavegitops', 'grafana'];

    constructor(config) {
        super();
        this.weavegitops = new ConfigAppsApp(config.weavegitops);
        this.grafana = new ConfigAppsApp(config.grafana);
    }

    validate() {
        super.validate();
        this.weavegitops.validate();
        this.grafana.validate();
    }
}

class ConfigAppsApp extends BaseConfig {
    required = ['adminPassword'];

    constructor(config) {
        super();
        this.adminPassword = config.adminPassword;
    }
}

class ConfigNetwork extends BaseConfig {
    required = ['loadBalancerRange', 'kubeVip', 'gateway', 'ingress', 'clusterCidr', 'serviceCidr'];
    patterns = {
        loadBalancerRange: /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}-(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/,
        kubeVip: /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/,
        gateway: /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/,
        ingress: /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/,
        clusterCidr: /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/,
        serviceCidr: /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/,
    };

    constructor(config) {
        super();
        this.loadBalancerRange = config.loadBalancerRange;
        this.kubeVip = config.kubeVip;
        this.gateway = config.gateway;
        this.ingress = config.ingress;
        this.clusterCidr = config.clusterCidr;
        this.serviceCidr = config.serviceCidr;
    }
}

class ConfigGithub extends BaseConfig {
    required = ['public', 'url', 'webhook'];
    patterns = {
        url: /^https:\/\/github.com\/.+\/.+$/,
    };

    constructor(config) {
        super();
        this.public = config.public;
        this.url = config.url;
        this.webhook = new ConfigGithubWebhook(config.webhook);
    }

    validate() {
        super.validate();
        this.webhook.validate();
    }
}

class ConfigGithubWebhook extends BaseConfig {
    required = ['secret'];

    constructor(config) {
        super();
        this.secret = config.secret;
    }
}

class ConfigCloudflare extends BaseConfig {
    required = ['domain', 'apiToken', 'tunnel'];
    patterns = {
        domain: /^.+\..+$/
    };

    constructor(config) {
        super();
        this.domain = config.domain;
        this.apiToken = config.apiToken;
        this.tunnel = new ConfigCloudflareTunnel(config.tunnel);
    }

    validate() {
        super.validate();
        this.tunnel.validate();
    }
}

class ConfigCloudflareTunnel extends BaseConfig {
    required = ['accountTag', 'secret', 'id'];

    constructor(config) {
        super();
        this.accountTag = config.accountTag;
        this.secret = config.secret;
        this.id = config.id;
    }
}

class ConfigNode extends BaseConfig {
    required = ['address', 'username', 'password', 'control'];
    patterns = {
        address: /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/,
    };

    constructor(config, index) {
        super();
        this.name = config.name;
        this.address = config.address;
        this.username = config.username;
        this.password = config.password;
        this.control = config.control;

        if (!this.name) this.name = `${defaultHostPrefix}-${index}`;
    }
}
//#endregion

//#region Utils
async function doAction(type, fn) {
    let action = 'Verifying';
    if (type == 'configure') action = 'Configuring';

    logger.info(`${action} ${fn.name.replace(type, '')}...`);
    await spinner(() => fn());
}

async function validIp(ip) {
    try {
        const result = await $`ipcalc "${ip}"`.quiet();
        return result.stdout.indexOf('INVALID') == -1;
    } catch (e) {
        logger.debug(e.message);
        return false;
    }
}

async function exit() {
    process.exit(1);
}

async function readConfig() {
    try {
        const config = await readFile('config.yaml', 'utf8');
        const parsedConfig = parse(config);
        return new Config(parsedConfig);
    } catch (e) {
        logger.error(`Error reading config.yaml: ${e.message}`);
        exit();
    }
}

async function isUnlocked() {
    try {
        await access('configure.lock');
    } catch (e) {
        logger.error('Configuration not verified, run with --verify first');
        logger.debug(e.message);
        exit();
    }

    try {
        const md5sum = await readFile('configure.lock');
        const filemd5sum = (await $`md5sum config.yaml`.quiet()).stdout;
        if (md5sum.toString().trim() != filemd5sum.trim()) {
            throw new Error(`md5sum '${md5sum.toString().trim()}' does not match '${filemd5sum.trim()}'`);
        }
    } catch (e) {
        logger.error('Configuration changed since last verify, run with --verify first');
        logger.debug(e.message);
        exit();
    }
}

async function lock() {
    try {
        await rm('configure.lock');
    } catch (e) {
        logger.error('Could not lock configuration');
        logger.debug(e.message);
        exit();
    }
}

async function unlock() {
    const md5 = (await $`md5sum config.yaml`.quiet()).stdout;
    await writeFile('configure.lock', md5.toString().trim());
}

async function configureFile(source, destination, encrypt = false) {
    const config = await readConfig();
    try {
        await $`cp "${source}" "${destination}"`.quiet();
        await replaceTokens(destination, config);
        if (encrypt) await sopsEncrypt(destination);
    } catch (e) {
        logger.error(`Could not move ${source} to ${destination}`);
        logger.debug(e.message);
        exit();
    }
}

async function replaceTokens(file, object) {
    const fileContents = await readFile(file, 'utf8');
    const newContents = fileContents.replace(/!{(.+?)}/g, (_, token) => {
        const value = deepFind(token, object);
        return value;
    });
    await writeFile(file, newContents);
}

function deepFind(path, config) {
    return path.split('.').reduce((a, v) => a[v], config);
}

async function sopsEncrypt(file) {
    try {
        await $`sops --encrypt --in-place "${file}"`.quiet();
    } catch (e) {
        logger.error(`Could not encrypt ${file}`);
        logger.debug(e.message);
        exit();
    }
}
//#endregion

//#region Configure
async function runConfigure() {
    if (!testing) await isUnlocked();

    const actions = [
        configureTemplates,
        configureAnsibleHosts,
        configureAnsibleSecrets,
        configureGithubWebhook,
        configureWeaveGitops,
        configureGrafana];

    for await (const action of actions) {
        await doAction('configure', action);
    }

    if (!testing) await lock();
    logger.info('Configuration installation completed successfully');
}

async function configureTemplates() {
    // Generate sops config
    configureFile(path.join(tmpl, '.sops.yaml'), path.join(__dirname, '.sops.yaml'));

    logger.info('- Generated .sops.yaml');

    // Generate cluster settings
    configureFile(path.join(tmpl, 'kubernetes', 'flux', 'cluster-settings.yaml'), path.join(__dirname, 'kubernetes', 'flux', 'vars', 'cluster-settings.yaml'));
    configureFile(path.join(tmpl, 'kubernetes', 'flux', 'cluster.yaml'), path.join(__dirname, 'kubernetes', 'flux', 'config', 'cluster.yaml'));

    logger.info('- Generated cluster settings');

    // Generate secrets
    configureFile(path.join(tmpl, 'kubernetes', 'cluster-secrets.sops.yaml'),
        path.join(__dirname, 'kubernetes', 'flux', 'vars', 'cluster-secrets.sops.yaml'), true);

    configureFile(path.join(tmpl, 'kubernetes', 'cert-manager-secret.sops.yaml'),
        path.join(__dirname, 'kubernetes', 'apps', 'cert-manager', 'cert-manager', 'issuers', 'secret.sops.yaml'), true);

    configureFile(path.join(tmpl, 'kubernetes', 'cloudflared-secret.sops.yaml'),
        path.join(__dirname, 'kubernetes', 'apps', 'networking', 'cloudflared', 'app', 'secret.sops.yaml'), true);

    configureFile(path.join(tmpl, 'kubernetes', 'external-dns-secret.sops.yaml'),
        path.join(__dirname, 'kubernetes', 'apps', 'networking', 'external-dns', 'app', 'secret.sops.yaml'), true);

    logger.info('- Generated secrets');

    // Generate ansible settings
    configureFile(path.join(tmpl, 'ansible', 'supplemental.yml'),
        path.join(__dirname, 'ansible', 'inventory', 'group_vars', 'kubernetes', 'supplemental.yml'));

    logger.info('- Generated ansible settings');
}

async function configureAnsibleHosts() {
    const config = await readConfig();
    const yamlDoc = new yaml.Document();
    const filePath = path.join(__dirname, 'ansible', 'hosts.yml');

    const hosts = {
        kubernetes: {
            children: {
                master: {
                    hosts: {}
                }
            }
        }
    }

    for await (const node of config.nodes) {
        if (node.control) {
            hosts.kubernetes.children.master.hosts[node.name] = {
                ansible_host: node.address
            }
            logger.info(`- Added ${node.name} to master group`);
        } else {
            if (!hosts.kubernetes.children.worker) hosts.kubernetes.children.worker = { hosts: {} }
            hosts.kubernetes.children.worker.hosts[node.name] = {
                ansible_host: node.address
            }
            logger.info(`- Added ${node.name} to worker group`);
        }
    }

    yamlDoc.contents = hosts;
    await writeFile(filePath, '---\n');
    await appendFile(filePath, yamlDoc.toString());

    logger.info('- Generated ansible hosts');
}

async function configureAnsibleSecrets() {
    const config = await readConfig();
    const yamlDoc = new yaml.Document();
    const filePath = path.join(__dirname, 'ansible', 'inventory', 'host_vars');

    const secret = {
        kind: 'Secret',
        ansible_user: '',
        ansible_become_pass: ''
    }

    for await (const node of config.nodes) {
        secret.ansible_user = node.username;
        secret.ansible_become_pass = node.password;

        yamlDoc.contents = secret;
        await writeFile(path.join(filePath, `${node.name}.sops.yml`), yamlDoc.toString());
        sopsEncrypt(path.join(filePath, `${node.name}.sops.yml`));

        logger.info(`- Generated ansible secret for ${node.name}`);
    }
}

async function configureGithubWebhook() {
    const config = await readConfig();

    if (config.github.webhook.secret == 'generated') {
        config.github.webhook.secret = crypto.randomBytes(32).toString('hex');

        logger.info(`- Generated github webhook secret`);
    }

    await writeFile('config.yaml', config.toYaml());

    configureFile(path.join(tmpl, 'kubernetes', 'github-webhook-token-secret.sops.yaml'),
        path.join(__dirname, 'kubernetes', 'apps', 'flux-system', 'addons', 'webhooks', 'github', 'secret.sops.yaml'), true);

    logger.info(`- Generated github webhook secret file`);
}

async function configureWeaveGitops() {
    const config = await readConfig();

    if (config.apps.weavegitops.adminPassword == 'generated') {
        const generatedPassword = crypto.randomBytes(32).toString('hex');
        const bhash = (await $`echo -n "${generatedPassword}" | gitops get bcrypt-hash`.quiet()).stdout.trim();

        config.apps.weavegitops.adminPassword = bhash;

        await writeFile('config.yaml', config.toYaml());

        logger.info(`- Generated weave gitops admin password`);
    }

    configureFile(path.join(tmpl, 'kubernetes', 'weave-gitops-secret.sops.yaml'),
        path.join(__dirname, 'kubernetes', 'apps', 'flux-system', 'weave-gitops', 'app', 'secret.sops.yaml'), true);

    logger.info(`- Generated weave gitops secret file`);
}

async function configureGrafana() {
    const config = await readConfig();

    if (config.apps.grafana.adminPassword == 'generated') {
        config.apps.grafana.adminPassword = crypto.randomBytes(32).toString('hex');

        logger.info(`- Generated grafana admin password`);
    }

    await writeFile('config.yaml', config.toYaml());

    configureFile(path.join(tmpl, 'kubernetes', 'grafana-admin-secret.sops.yaml'),
        path.join(__dirname, 'kubernetes', 'apps', 'monitoring', 'grafana', 'app', 'secret.sops.yaml'), true);

    logger.info(`- Generated grafana secret file`);
}
//#endregion

//#region Verify
async function verifyConfigure() {
    const actions = [
        verifyConfig,
        verifyPackages,
        verifyControlCount,
        verifyHosts,
        verifyMetallb,
        verifyKubevip,
        verifyClusterServiceCidrs,
        verifyAddressing,
        verifyAge,
        verifyGitRepository,
        verifyCloudFlare];

    for await (const action of actions) {
        await doAction('verify', action);
    }

    await unlock();
    logger.info('Configuration verified successfully');
}

async function verifyConfig() {
    const config = await readConfig();
    try {
        config.validate();
        logger.info('- Configuration is valid');
    } catch (e) {
        logger.error(e.message);
        exit();
    }
}

async function verifyPackages() {
    let hasErrors = false;

    for await (const binary of requiredPackages) {
        try {
            await which(binary);
            logger.info(`- Found binary ${binary}`);
        } catch (e) {
            hasErrors = true;
            logger.error(`Could not find binary ${binary}`);
            logger.debug(e.message);
        }
    };

    if (hasErrors) exit();
}

async function verifyControlCount() {
    const config = await readConfig();
    const controlCount = config.nodes.filter(node => node.control).length;

    if (controlCount % 2 == 0) {
        logger.error('Control count must be an odd number greater than 0');
        exit();
    } else {
        logger.info(`- Control count is ${controlCount}`);
    }
}

async function verifyHosts() {
    const config = await readConfig();

    let hasErrors = false;

    for await (const node of config.nodes) {
        if (node.address == config.network.kubeVip) {
            logger.error(`Node ${node.name} @ ${node.address} cannot have the same IP address as kube-vip`);
            hasErrors = true;
        }

        if (node.address == config.network.gateway) {
            logger.error(`Node ${node.name} @ ${node.address} cannot have the same IP address as the gateway`);
            hasErrors = true;
        }

        try {
            await $`ssh -q -o BatchMode=yes -o ConnectTimeout=5 "${node.username}"@"${node.address}" true`.quiet();
            logger.info(`- SSH to ${node.name} @ ${node.address} successful`);
        } catch (e) {
            logger.error(`Could not SSH to ${node.name} @ ${node.address}, did you copy your SSH key?`);
            logger.debug(e.message);
            hasErrors = true;
        }
    }

    if (hasErrors) exit();
}

async function verifyMetallb() {
    const config = await readConfig();
    const [ start, end ] = config.network.loadBalancerRange.split('-');
    const gateway = config.network.gateway;
    const ingress = config.network.ingress;

    let hasErrors = false;

    if (!await validIp(start)) {
        logger.error(`Load balancer range IP address ${start} is not valid`);
        hasErrors = true;
    }

    if (!await validIp(end)) {
        logger.error(`Load balancer range IP address ${end} is not valid`);
        hasErrors = true;
    }

    if (!await validIp(gateway)) {
        logger.error(`Gateway IP address ${gateway} is not valid`);
        hasErrors = true;
    }

    if (!await validIp(ingress)) {
        logger.error(`Ingress IP address ${ingress} is not valid`);
        hasErrors = true;
    }

    if (hasErrors) exit();

    logger.info(`- Load balancer range is ${start}-${end}`);
    logger.info(`- Gateway is ${gateway}`);
    logger.info(`- Ingress is ${ingress}`);
}

async function verifyKubevip() {
    const config = await readConfig();
    const kubeVip = config.network.kubeVip;

    if (!await validIp(kubeVip)) {
        logger.error(`kube-vip IP address ${kubeVip} is not valid`);
        exit();
    }

    logger.info(`- kube-vip is ${kubeVip}`);
}

async function verifyClusterServiceCidrs() {
    const config = await readConfig();
    const clusterCidr = config.network.clusterCidr;
    const serviceCidr = config.network.serviceCidr;

    let hasErrors = false;

    if (!await validIp(clusterCidr)) {
        logger.error(`Cluster CIDR IP address ${clusterCidr} is not valid`);
        hasErrors = true;
    } else {
        logger.info(`- Cluster CIDR is ${clusterCidr}`);
    }

    if (!await validIp(serviceCidr)) {
        logger.error(`Service CIDR IP address ${serviceCidr} is not valid`);
        hasErrors = true;
    } else {
        logger.info(`- Service CIDR is ${serviceCidr}`);
    }

    if (hasErrors) exit();
}

async function verifyAddressing() {
    const config = await readConfig();

    const kubeVip = config.network.kubeVip;
    const gateway = config.network.gateway;
    const ingress = config.network.ingress;

    const metallbSubnetMin = config.network.loadBalancerRange.split('-')[0].substring(0, config.network.loadBalancerRange.split('-')[0].lastIndexOf('.'));
    const metallbSubnetMax = config.network.loadBalancerRange.split('-')[1].substring(0, config.network.loadBalancerRange.split('-')[1].lastIndexOf('.'));
    const kubeVipSubnet = config.network.kubeVip.substring(0, config.network.kubeVip.lastIndexOf('.'));

    const metallbOctetMin = parseInt(config.network.loadBalancerRange.split('-')[0].split('.')[3]);
    const metallbOctetMax = parseInt(config.network.loadBalancerRange.split('-')[1].split('.')[3]);

    let hasErrors = false;

    if (metallbSubnetMin != metallbSubnetMax) {
        logger.error(`Load balancer range subnet ${config.network.loadBalancerRange} must be in the same subnet`);
        hasErrors = true;
    } else {
        logger.info(`- Load balancer range subnet is ${metallbSubnetMin}`);
    }

    config.nodes.forEach(node => {
        const nodeSubnet = node.address.substring(0, node.address.lastIndexOf('.'));
        if (nodeSubnet != metallbSubnetMin) {
            logger.error(`Node ${node.name} @ ${node.address} must be in the same subnet as the metallb range ${config.network.loadBalancerRange}`);
            hasErrors = true;
        } else {
            logger.info(`- Node ${node.name} @ ${node.address} is in the same subnet as the metallb range ${config.network.loadBalancerRange}`);
        }
    });

    if (kubeVipSubnet != metallbSubnetMin) {
        logger.error(`kube-vip ${config.network.kubeVip} must be in the same subnet as the metallb range ${config.network.loadBalancerRange}`);
        hasErrors = true;
    } else {
        logger.info(`- kube-vip ${config.network.kubeVip} is in the same subnet as the metallb range ${config.network.loadBalancerRange}`);
    }

    let gatewayFound = false;
    let ingressFound = false;

    for (let i = metallbOctetMin; i <= metallbOctetMax; i++) {
        const metallbIp = `${metallbSubnetMin}.${i}`;

        if (metallbIp == kubeVip) {
            logger.error(`kube-vip ${kubeVip} cannot be in metallb range ${config.network.loadBalancerRange}`);
            hasErrors = true;
        }

        if (metallbIp == gateway) gatewayFound = true;
        if (metallbIp == ingress) ingressFound = true;

        if (config.nodes.filter(node => node.address == metallbIp).length > 0) {
            logger.error(`Node ${node.name} @ ${node.address} cannot in metallb range ${config.network.loadBalancerRange}`);
            hasErrors = true;
        }
    }

    if (!gatewayFound) {
        logger.error(`Gateway ${gateway} should be in metallb range ${config.network.loadBalancerRange}`);
        hasErrors = true;
    } else {
        logger.info(`- Gateway ${gateway} is in metallb range ${config.network.loadBalancerRange}`);
    }

    if (!ingressFound) {
        logger.error(`Ingress ${ingress} should be in metallb range ${config.network.loadBalancerRange}`);
        hasErrors = true;
    } else {
        logger.info(`- Ingress ${ingress} is in metallb range ${config.network.loadBalancerRange}`);
    }

    if (hasErrors) exit();
}

async function verifyAge() {
    const config = await readConfig();

    let hasErrors = false;

    try {
        const result = /^age.*/.test(config.ageKey);
        if (!result) throw new Error();

        logger.info(`- ageKey is valid`);
    } catch (e) {
        logger.error(`- ageKey is not valid`);
        logger.debug(e.message);
        hasErrors = true;
    }

    let ageFileContents;
    let ageKeyFilePath = ageKeyFile;
    try {
        if (ageKeyFilePath.startsWith('~')) ageKeyFilePath = ageKeyFilePath.replace('~', os.homedir());

        ageFileContents = await readFile(ageKeyFilePath, 'utf8');
    } catch (e) {
        logger.error(`- Unable to find age key files at ${ageKeageKeyFilePathyFile} ${e.message}`);
        logger.debug(e.message);
        hasErrors = true;
    }

    if (ageFileContents) {
        if (ageFileContents.indexOf(config.ageKey) == -1) {
            logger.error(`- ageKey does not match key in ${ageKeyFilePath}`);
            hasErrors = true;
        } else {
            logger.info(`- ageKey does match key in ${ageKeyFilePath}`);
        }
    }

    if (hasErrors) exit();
}

async function verifyGitRepository() {
    const config = await readConfig();

    try {
        await $`git ls-remote ${config.github.url} HEAD`.quiet();
        logger.info(`- Able to access git repository ${config.github.url}`);
    } catch (e) {
        logger.error(`- Unable to access git repository ${config.github.url}`);
        logger.debug(e.message);
        exit();
    }
}

async function verifyCloudFlare() {
    const config = await readConfig();

    let hasErrors = false;

    try {
        const result = await fetch(`https://api.cloudflare.com/client/v4/zones?name=${config.cloudflare.domain}&status=active`, {
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${config.cloudflare.apiToken}`
            }
        });
        const jsonResult = await result.json();
        if (jsonResult.success && jsonResult.result.length > 0) {
            logger.info(`- Able to access CloudFlare API`);
        } else if (jsonResult.errors) {
            throw new Error(JSON.stringify(jsonResult.errors));
        } else {
            throw new Error();
        }
    } catch (e) {
        logger.error(`- Unable to properly access CloudFlare API, check your API token and domain ${e.message}`);
        hasErrors = true;
    }

    try {
        const result = await fetch(`https://api.cloudflare.com/client/v4/accounts/${config.cloudflare.tunnel.accountTag}/cfd_tunnel/${config.cloudflare.tunnel.id}`, {
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${config.cloudflare.apiToken}`
            }
        });
        const jsonResult = await result.json();
        if (jsonResult.success && jsonResult.result && Object.values(jsonResult.result).length > 0) {
            logger.info(`- Able to access CloudFlare Tunnel information`);
        } else if (jsonResult.errors) {
            throw new Error(JSON.stringify(jsonResult.errors));
        } else {
            throw new Error();
        }
    } catch (e) {
        logger.error(`- Unable to get Cloudflare Tunnel information ${e.message}`);
        hasErrors = true;
    }

    if (hasErrors) exit();
}
//#endregion
