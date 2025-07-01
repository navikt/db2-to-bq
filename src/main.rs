use color_eyre::eyre::{Result, eyre};
use ibm_db::{
    Connection,
    ResultSetState::{Data, NoData},
    Statement, create_environment_v3,
    safe::AutocommitOn,
};

fn main() -> Result<()> {
    color_eyre::install()?;

    let a = std::env::var("IBM_DB_HOME");
    println!("Hello, {a:?}!");

    let env = create_environment_v3().map_err(|e| {
        let error_message = e.map_or_else(
            || "Empty option (no error struct)".to_string(),
            |error| format!("{error}"),
        );
        eyre!("When `create_environment_v3`: {error_message}")
    })?;
    let connection = env
        .connect("dbname", "dbuser", "dbpass")
        .map_err(|e| eyre!("When instatiating connection: {e}"))?;
    execute_statement(&connection)?;
    Ok(())
}

fn execute_statement(conn: &Connection<'_, AutocommitOn>) -> Result<()> {
    let statement_executor = Statement::with_parent(conn).unwrap();

    let sql = "select * from foo;";
    match statement_executor.exec_direct(sql).unwrap() {
        NoData(_) => println!("statement `{sql}` resulted in no returned data"),
        Data(mut data) => {
            let columns = data.num_result_cols()?;
            while let Some(mut cursor) = data.fetch().unwrap() {
                for column_index in 1..=columns {
                    match cursor.get_data::<&str>(column_index as u16)? {
                        Some(value) => print!(" {value}"),
                        None => print!(" NULL"),
                    }
                }
            }
        }
    }
    Ok(())
}
