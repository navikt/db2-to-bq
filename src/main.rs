fn main() {
    let a = std::env::var("IBM_DB_HOME");
    println!("Hello, {a:?}!");
}
