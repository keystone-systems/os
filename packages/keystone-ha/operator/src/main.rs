use kube::{Client, Api};
use keystone_ha_defs::grant::Grant;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Starting Keystone HA Operator...");
    
    // In a real environment, we would connect to the cluster
    // let client = Client::try_default().await?;
    // let grants: Api<Grant> = Api::all(client);
    
    // For now, just prove we can use the types
    println!("Grant type is available: {}", std::any::type_name::<Grant>());
    
    Ok(())
}