import React, { Component } from 'react'
import { Route, Link } from 'react-router-dom'
import StatActivityContainer from './StatActivityContainer'
import Backup from './backup'


const NavItem = ({children, to, exact}) => {
    return (
        <Route path={to} exact={exact} children={({match}) => (
            <li className={match ? 'nav-item active' : 'nav-item' }>
                <Link to={to}>{children}</Link>
            </li>
        )}/>
    )
}

const Header = () => {
  return (
    <ul className="nav nav-tabs">
      <NavItem exact to="/postgres">Stat activity</NavItem>
      <NavItem to="/postgres/backup">Backup</NavItem>
    </ul>
  )

}

class PostgresHome extends Component{
  render(){
    return (
      <div>
        <h2>Postgres</h2>
        <Header />
        <Route exact path='/postgres' component={StatActivityContainer} />
        <Route path='/postgres/stat_activity' component={StatActivityContainer} /> 
        <Route path='/postgres/backup' exact={false} component={Backup} />
      
      </div>
    )
  }
}

export default PostgresHome