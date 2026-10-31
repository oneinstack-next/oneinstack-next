# Security finding handoff

The imported CodeRabbit report contains 90 LLM findings with unloaded source evidence, not 90 independently reproduced vulnerabilities. This modernization does not perform the separate full vulnerability triage or close findings. Original line numbers are baseline locations; re-locate them on the new diff.

## Shared interfaces and changed surfaces

- All artifact consumers now call `Download_Artifact` with explicit filenames. Identity/platform/trust resolution, fallback, cache verification, retry and atomic publication live in `include/download.sh` plus `include/source.sh`. Do not add an independent downloader to repair a finding.
- Network version data is parsed with jq/allowlisted data readers. `versions.txt` is never sourced. Local options remain a trusted administrator configuration file and still need separate review where historical writers interpolate credentials/data.
- Nginx frontend rendering, complete-tree validation, certificate deployment and binary activation share `include/nginx_config.sh` and a lock. Apache/Tomcat frontend activation uses a rollback set. New Nginx DNS-01 uses pre-exported credentials; the historical standalone Apache DNS parameter flow remains a review target.
- Self-update no longer executes the historical updater path. Disabling a vulnerable/unverifiable path is not evidence that all related historical findings were reproduced or fixed in a released version.
- Default phpinfo publication was removed while normal demo acquisition became opt-in. Backup tool downloads moved to private staging; backup credential/deletion/retention behavior was not comprehensively rewritten.

## Deferred security scope

Database authentication windows, password/SQL escaping, FPM sockets, SSH host-key policy, backup retention/deletion, secret command arguments, package repository signature policy, and application-specific rewrite vulnerabilities remain the dedicated security task. New shared interfaces do not establish that these unrelated paths are safe.

## Imported findings and review routing

| Finding ID | Baseline location | Severity | Routing |
| --- | --- | --- | --- |
| `f8ee2a28-16bb-4271-b87e-7a65e6f5f004` | `vhost.sh:840` | low | Changed surface: revalidate against new contracts |
| `b802bfaf-3399-4d1d-888d-3545ed17bc28` | `vhost.sh:633` | low | Changed surface: revalidate against new contracts |
| `965597ad-87d0-4a6f-ae39-5b642f2efb46` | `vhost.sh:714` | low | Changed surface: revalidate against new contracts |
| `83d45de7-f9b4-4c6d-9983-1089cb6f1f59` | `tools/mabs.sh:157` | low | Separate security review; no closure claimed |
| `703070af-e9c8-483d-bb00-d454f0bbd2d3` | `vhost.sh:797` | medium | Changed surface: revalidate against new contracts |
| `6e500e96-c2d9-4b45-9bf1-180bc7086bda` | `vhost.sh:397` | medium | Changed surface: revalidate against new contracts |
| `6d57333f-e371-4908-a640-b6b74263d4e9` | `vhost.sh:885` | low | Changed surface: revalidate against new contracts |
| `3efa1309-51c6-448e-a4a1-d79558c896fb` | `vhost.sh:230` | medium | Changed surface: revalidate against new contracts |
| `3ef8f509-a2de-40c9-b06f-be549586125c` | `reset_db_root_password.sh:92` | medium | Separate security review; no closure claimed |
| `3781a3f4-9ca1-4029-ad3d-3fc8c45e0c4b` | `tools/mscp.exp:75` | medium | Separate security review; no closure claimed |
| `2e9ee136-6553-47ac-8466-c79ca8cda2b0` | `tools/db_bk.sh:31` | low | Separate security review; no closure claimed |
| `20dc754f-e167-4cec-9bc7-6387842fd789` | `tools/mssh.exp:38` | medium | Separate security review; no closure claimed |
| `f993a9ee-285d-4dc6-bc73-9d826a10440a` | `include/mongodb.sh:57` | low | Separate security review; no closure claimed |
| `f88d15bf-f3bc-426e-bfa4-9fd7c8dd9d26` | `include/percona-8.4.sh:206` | medium | Separate security review; no closure claimed |
| `f879c124-0eeb-4f1f-b1fe-70cc95ebe417` | `include/download.sh:6` | high | Changed surface: revalidate against new contracts |
| `f6e5e722-3b07-4547-b0ab-cbb108f358f8` | `include/upgrade_web.sh:174` | medium | Changed surface: revalidate against new contracts |
| `ec7187ea-0915-47c9-8f0e-7e678fbcb1cc` | `include/mysql-5.7.sh:206` | medium | Separate security review; no closure claimed |
| `e13ab60a-0c33-422c-9eb0-7d2eeb1d9463` | `include/upgrade_phpmyadmin.sh:38` | medium | Changed surface: revalidate against new contracts |
| `ddd3da21-e6fd-4cf0-bd0a-0bdb288dfee9` | `include/upgrade_web.sh:18` | medium | Changed surface: revalidate against new contracts |
| `dc1c2ae5-3404-4455-9ca0-2eff9217cbf8` | `include/upgrade_script.sh:23` | medium | Changed surface: revalidate against new contracts |
| `db70bdb8-df7c-4430-b9c5-f30742692a44` | `include/percona-8.0.sh:200` | medium | Separate security review; no closure claimed |
| `ce992497-6b2e-470d-bb10-10d39fb800ae` | `include/upgrade_script.sh:14` | medium | Changed surface: revalidate against new contracts |
| `cd4ac5d0-93c0-4394-9d6d-ee9da9732f87` | `src/php5.3patch:49` | low | Separate security review; no closure claimed |
| `bc840c8b-2ec8-49ef-9efa-9619c1df0c7f` | `include/phpmyadmin.sh:20` | medium | Separate security review; no closure claimed |
| `ba0246a2-961b-4f88-9d38-815e46b2c312` | `include/mysql-8.0.sh:207` | medium | Separate security review; no closure claimed |
| `b4744e27-9429-4137-b0fd-b6e63d105674` | `include/mysql-8.0.sh:199` | medium | Separate security review; no closure claimed |
| `b2dc2b16-bf62-4e53-bfed-bc8f80c33b15` | `include/upgrade_script.sh:10` | low | Changed surface: revalidate against new contracts |
| `abfdb483-0a7c-4681-b7a6-8758dad4a25b` | `include/upgrade_web.sh:338` | medium | Changed surface: revalidate against new contracts |
| `a63b9191-553a-4c62-899d-0a6012ff433f` | `include/upgrade_script.sh:15` | medium | Changed surface: revalidate against new contracts |
| `a5b77165-524e-4f55-bd53-e163e1f11949` | `include/upgrade_script.sh:52` | medium | Changed surface: revalidate against new contracts |
| `9cec8569-1849-4e18-be12-b91affab6be3` | `include/pecl_xdebug.sh:30` | low | Changed surface: revalidate against new contracts |
| `95d01b9b-02bd-411a-8722-79a8df5453a7` | `include/upgrade_memcached.sh:17` | medium | Changed surface: revalidate against new contracts |
| `814e0104-2209-4803-aef7-4a2db72aabc3` | `include/upgrade_web.sh:75` | medium | Changed surface: revalidate against new contracts |
| `7f0d6a3e-9021-44ac-b035-626df148f06e` | `include/upgrade_web.sh:109` | medium | Changed surface: revalidate against new contracts |
| `7b2cc67d-9ab2-4b96-ad19-f7a3463cc450` | `include/mphp.sh:68` | medium | Separate security review; no closure claimed |
| `7511447a-0582-4784-80ce-632db9f8d36e` | `include/init_Debian.sh:26` | low | Separate security review; no closure claimed |
| `72d6c8fa-3162-4c5d-bfdb-b795ca73b259` | `include/download.sh:6` | medium | Changed surface: revalidate against new contracts |
| `6b04aaea-c5e2-4899-b0a5-cf710b5d7d37` | `include/pecl_xdebug.sh:29` | low | Changed surface: revalidate against new contracts |
| `68fd0f65-5b85-4db0-ae55-bba4059cf4fe` | `install.sh:69` | low | Changed surface: revalidate against new contracts |
| `5a91c4d1-415e-4d18-9be3-ea249e34e436` | `pureftpd_vhost.sh:115` | low | Separate security review; no closure claimed |
| `599e5757-b00e-4c1a-b1a7-eddd25c0cbfb` | `include/upgrade_db.sh:80` | medium | Changed surface: revalidate against new contracts |
| `561a261e-d18c-4d2e-a536-f6287c520cd5` | `include/upgrade_php.sh:19` | medium | Changed surface: revalidate against new contracts |
| `5212e317-f96f-4bf6-8504-fa4fe6d532ee` | `include/upgrade_db.sh:163` | medium | Changed surface: revalidate against new contracts |
| `501b34c3-ee76-4516-9154-2ef8d2596d2b` | `include/pecl_imap.sh:15` | medium | Changed surface: revalidate against new contracts |
| `47cc73c2-8a6c-420f-9abd-ba648ac6607b` | `include/download.sh:6` | medium | Changed surface: revalidate against new contracts |
| `4335b001-d73c-4394-bf1c-3c6f29536fa2` | `include/php-5.3.sh:188` | medium | Separate security review; no closure claimed |
| `40146f82-a6b7-4690-a765-2a1715054b05` | `include/upgrade_web.sh:235` | medium | Changed surface: revalidate against new contracts |
| `3ed61730-2794-497e-a311-ed2e708a39bc` | `include/upgrade_script.sh:13` | medium | Changed surface: revalidate against new contracts |
| `3e275abf-24c7-4899-8120-c194ee04b232` | `include/pureftpd.sh:34` | low | Separate security review; no closure claimed |
| `35ff77fa-e345-4324-9946-3a172cb1715c` | `include/postgresql.sh:22` | medium | Separate security review; no closure claimed |
| `35a431d4-1809-4ff3-920a-b2a964d937f7` | `include/download.sh:6` | medium | Changed surface: revalidate against new contracts |
| `311e66a0-8cc1-40d8-b049-0de5c93c9049` | `init.d/Tomcat-init:66` | medium | Separate security review; no closure claimed |
| `308570f5-7513-41f2-addb-89edb36b490a` | `install.sh:19` | medium | Changed surface: revalidate against new contracts |
| `2ec09c7c-2906-4790-a5ec-943ac78ea015` | `include/mongodb.sh:56` | medium | Separate security review; no closure claimed |
| `28b3e14a-48b5-46ca-ab14-6bdb284a7fa0` | `include/mariadb-11.8.sh:200` | low | Separate security review; no closure claimed |
| `288b40e1-e1b5-409f-9c95-c61c1f5610be` | `include/php-7.0.sh:208` | medium | Separate security review; no closure claimed |
| `2630d9ed-c6a4-473a-bacf-c6f3a4721dec` | `include/upgrade_phpmyadmin.sh:16` | medium | Changed surface: revalidate against new contracts |
| `22595378-3280-46dd-8e50-1bf8b3a4b8cd` | `include/mysql-8.4.sh:205` | medium | Separate security review; no closure claimed |
| `17c7333c-ad23-48dc-ba78-1caed49a17f5` | `include/upgrade_script.sh:27` | medium | Changed surface: revalidate against new contracts |
| `1381801c-3bc3-426a-9778-938092660463` | `include/upgrade_web.sh:300` | medium | Changed surface: revalidate against new contracts |
| `0ee1fabf-a8ad-4e42-9917-e04c82923417` | `include/download.sh:6` | medium | Changed surface: revalidate against new contracts |
| `0019c637-303a-43cb-b406-992d46e3f5d8` | `include/upgrade_redis.sh:16` | medium | Changed surface: revalidate against new contracts |
| `e42b8f69-86a0-415a-befe-243168b63cdd` | `backup_setup.sh:118` | medium | Changed surface: revalidate against new contracts |
| `e1794563-db48-4f79-b709-3a6d28cad291` | `include/check_download.sh:351` | medium | Changed surface: revalidate against new contracts |
| `de062a13-d3e9-431a-b7b6-b4f79749acbb` | `include/composer.sh:12` | medium | Changed surface: revalidate against new contracts |
| `d0d4f4c9-a627-4c3b-ba02-50e54de9878e` | `include/check_sw.sh:30` | low | Separate security review; no closure claimed |
| `c0a02408-d3d7-4df2-a67a-dff4be16556b` | `include/check_download.sh:174` | medium | Changed surface: revalidate against new contracts |
| `b79193d1-de5f-424d-acfb-3457dd7e3770` | `include/check_download.sh:120` | high | Changed surface: revalidate against new contracts |
| `b16244e1-f5ba-4dac-ac31-af41d8a16228` | `backup_setup.sh:437` | medium | Changed surface: revalidate against new contracts |
| `af5110ee-50ec-4945-a31e-615fd88ddf05` | `backup.sh:212` | low | Separate security review; no closure claimed |
| `a56624cf-8d39-4cf0-83bd-d9dcb81ecb73` | `include/check_download.sh:250` | medium | Changed surface: revalidate against new contracts |
| `80539430-19e5-47c8-92e5-f1878c843302` | `config/wordpress.conf:5` | medium | Separate security review; no closure claimed |
| `7d96b6d6-e65a-40f1-a5d0-bb03b7b88192` | `include/check_download.sh:195` | medium | Changed surface: revalidate against new contracts |
| `72bef64f-9920-4d2d-a0a5-0174d3da0b3c` | `include/check_download.sh:408` | medium | Changed surface: revalidate against new contracts |
| `7236b311-d24f-4248-bde7-a7a32b5d80c0` | `config/magento2.conf:132` | medium | Separate security review; no closure claimed |
| `6ecc5018-2107-4884-bce0-0bc68aff1413` | `include/download.sh:6` | medium | Changed surface: revalidate against new contracts |
| `6e512507-27ec-43ac-a92e-df8814471445` | `include/check_download.sh:147` | medium | Changed surface: revalidate against new contracts |
| `5b92790a-8787-4e96-a285-ecdddba4e5da` | `backup_setup.sh:540` | medium | Changed surface: revalidate against new contracts |
| `58fe62b2-cfe1-431d-8a4a-c8072ce78324` | `backup_setup.sh:384` | medium | Changed surface: revalidate against new contracts |
| `53926e3a-8894-40d0-ae85-6b9967906c81` | `backup_setup.sh:239` | low | Changed surface: revalidate against new contracts |
| `5391ef92-b7a0-43ad-a9e6-372d161e48b5` | `config/nginx_apache.conf:101` | low | Changed surface: revalidate against new contracts |
| `48dc7375-1907-4f88-ab66-d361eb60a61f` | `backup_setup.sh:350` | medium | Changed surface: revalidate against new contracts |
| `43acae6b-6d24-4f4e-8e7f-c44867111497` | `backup_setup.sh:386` | low | Changed surface: revalidate against new contracts |
| `422f0dfa-dbab-44bc-b4ef-e0412ebc29ad` | `config/nginx_apache.conf:101` | low | Changed surface: revalidate against new contracts |
| `3ef28619-62b7-4213-83d3-16614678fb7c` | `backup.sh:86` | medium | Separate security review; no closure claimed |
| `31c67397-1170-4b9a-a11a-58e5075c8f76` | `include/check_download.sh:384` | medium | Changed surface: revalidate against new contracts |
| `256d7108-c912-4115-be5e-69899042d215` | `include/check_download.sh:287` | medium | Changed surface: revalidate against new contracts |
| `243a5814-2b95-41c4-937f-62413b58d4f3` | `include/check_download.sh:319` | medium | Changed surface: revalidate against new contracts |
| `1f2694a9-eaca-456b-b154-fb29dbfe489f` | `include/demo.sh:15` | low | Changed surface: revalidate against new contracts |
| `1d96cd60-fead-4cfd-a6e5-3a7f82e08d43` | `config/nginx_tomcat.conf:109` | low | Changed surface: revalidate against new contracts |
