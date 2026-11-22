//! Hızlı Paylaş: alma sunucusu (plan-core) + mDNS yayını ve cihaz keşfi (`mdns-sd`).

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use plan_core::quickshare::{self, Event, Server, ServerConfig, SERVICE_TYPE};
use plan_core::sync::Peer;
use std::collections::HashMap;
use std::sync::{mpsc::Sender, Arc, Mutex};

pub struct Share {
    server: Option<Server>,
    daemon: Option<ServiceDaemon>,
    pub devices: Arc<Mutex<Vec<Peer>>>,
    my_id: String,
}

fn local_name() -> String {
    std::env::var("HOSTNAME").or_else(|_| std::env::var("COMPUTERNAME")).unwrap_or_else(|_| "Plan".into())
}

impl Share {
    pub fn new(my_id: String) -> Share {
        Share { server: None, daemon: None, devices: Arc::default(), my_id }
    }

    pub fn running(&self) -> bool {
        self.server.is_some()
    }

    pub fn start(&mut self, cfg: ServerConfig, on_event: Arc<dyn Fn(Event) + Send + Sync>, on_devices: Sender<()>) -> Result<(), String> {
        if self.running() {
            return Ok(());
        }
        let server = Server::start(cfg, 0, on_event).map_err(|e| e.to_string())?;
        let daemon = ServiceDaemon::new().map_err(|e| e.to_string())?;
        let ty = format!("{SERVICE_TYPE}.local.");
        let name = local_name();
        let inst = quickshare::service_name(&self.my_id);
        let props: HashMap<String, String> = [("n".to_string(), name.clone()), ("i".to_string(), self.my_id.clone())].into();
        let info = ServiceInfo::new(&ty, &inst, &format!("{inst}.local."), "", server.port, Some(props))
            .map_err(|e| e.to_string())?
            .enable_addr_auto();
        daemon.register(info).map_err(|e| e.to_string())?;

        // Ağdaki diğer açık cihazları bul (kendimizi listeleme)
        let rx = daemon.browse(&ty).map_err(|e| e.to_string())?;
        let devices = self.devices.clone();
        let my_id = self.my_id.clone();
        std::thread::spawn(move || {
            while let Ok(ev) = rx.recv() {
                match ev {
                    ServiceEvent::ServiceResolved(i) => {
                        let id = i.get_property_val_str("i").unwrap_or("").to_string();
                        let full = i.get_fullname().to_string();
                        let inst = full.split('.').next().unwrap_or("").to_string();
                        if id == my_id || inst == quickshare::service_name(&my_id) {
                            continue;
                        }
                        let Some(ip) = i.get_addresses_v4().into_iter().next().copied() else { continue };
                        let p = Peer {
                            id: inst.clone(),
                            name: i.get_property_val_str("n").unwrap_or(&inst).to_string(),
                            addr: format!("{ip}:{}", i.get_port()),
                        };
                        let mut d = devices.lock().unwrap();
                        d.retain(|x| x.id != p.id);
                        d.push(p);
                        d.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
                        let _ = on_devices.send(());
                    }
                    ServiceEvent::ServiceRemoved(_, full) => {
                        let inst = full.split('.').next().unwrap_or("").to_string();
                        devices.lock().unwrap().retain(|x| x.id != inst);
                        let _ = on_devices.send(());
                    }
                    ServiceEvent::SearchStopped(_) => break,
                    _ => {}
                }
            }
        });
        self.server = Some(server);
        self.daemon = Some(daemon);
        Ok(())
    }

    pub fn stop(&mut self) {
        if let Some(d) = self.daemon.take() {
            let _ = d.shutdown();
        }
        if let Some(mut s) = self.server.take() {
            s.stop();
        }
        self.devices.lock().unwrap().clear();
    }
}
