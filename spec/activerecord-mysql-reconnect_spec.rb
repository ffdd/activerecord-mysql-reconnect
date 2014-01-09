describe 'activerecord-mysql-reconnect' do
  it 'select all' do
    expect {
      expect(Employee.all.length).to eq(300024)
      mysql_restart
      expect(Employee.all.length).to eq(300024)
    }.to_not raise_error
  end

  it 'count' do
    expect {
      expect(Employee.count).to eq(300024)
      mysql_restart
      expect(Employee.count).to eq(300024)
    }.to_not raise_error
  end

  it 'on select' do
    expect {
      thread_running = false

      th = Thread.start {
        thread_running = true
        expect(Employee.where(:id => 1).pluck('sleep(15) * 0')).to eq([0])
        thread_running = false
      }

      th.abort_on_exception = true
      sleep 3
      expect(thread_running).to be_true
      mysql_restart
      expect(Employee.count).to be >= 300024
      th.join
    }.to_not raise_error
  end

  it 'on insert' do
    expect {
      thread_running = false

      th = Thread.start {
        thread_running = true
        emp = nil

        mysql2_error('MySQL server has gone away') do
          emp = Employee.create(
                  :emp_no     => 1,
                  :birth_date => Time.now,
                  :first_name => "' + sleep(15) + '",
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
        end

        thread_running = false
        expect(emp.id).to eq(300025)
        expect(emp.emp_no).to eq(1)
      }

      th.abort_on_exception = true
      sleep 3
      expect(thread_running).to be_true
      mysql_restart
      expect(Employee.count).to be >= 300024
      th.join
    }.to_not raise_error
  end

  it 'op update' do
    expect {
      thread_running = false

      th = Thread.start {
        thread_running = true
        emp = Employee.where(:id => 1).first
        emp.first_name = "' + sleep(15) + '"
        emp.last_name = 'ZapZapZap'

        mysql2_error('MySQL server has gone away') do
          emp.save!
        end

        thread_running = false

        emp = Employee.where(:id => 1).first
        expect(emp.last_name).to eq('ZapZapZap')
      }

      th.abort_on_exception = true
      sleep 3
      expect(thread_running).to be_true
      mysql_restart
      expect(Employee.count).to eq(300024)
      th.join
    }.to_not raise_error
  end

  it 'without_retry' do
    expect {
      ActiveRecord::Base.without_retry do
        Employee.count
        mysql_restart
        Employee.count
      end
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'transaction' do
    expect {
      expect(Employee.count).to eq(300024)

      mysql2_error('MySQL server has gone away') do
        ActiveRecord::Base.transaction do
          emp = Employee.create(
                  :emp_no     => 1,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300025)
          expect(emp.emp_no).to eq(1)
          mysql_restart
          emp = Employee.create(
                  :emp_no     => 2,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300025)
          expect(emp.emp_no).to eq(2)
        end
      end

      expect(Employee.count).to eq(300025)
    }.to_not raise_error
  end

  it 'retryable_transaction' do
    expect {
      expect(Employee.count).to eq(300024)

      mysql2_error('MySQL server has gone away') do
        ActiveRecord::Base.retryable_transaction do
          emp = Employee.create(
                  :emp_no     => 1,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300025)
          expect(emp.emp_no).to eq(1)
          mysql_restart
          emp = Employee.create(
                  :emp_no     => 2,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300026)
          expect(emp.emp_no).to eq(2)
          mysql_restart
          emp = Employee.create(
                  :emp_no     => 3,
                  :birth_date => Time.now,
                  :first_name => 'Scott',
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
          expect(emp.id).to eq(300027)
          expect(emp.emp_no).to eq(3)
        end
      end

      expect(Employee.count).to eq(300027)
    }.to_not raise_error
  end

  it 'retry new connection' do
    expect {
      ActiveRecord::Base.clear_all_connections!
      mysql_restart
      expect(Employee.count).to eq(300024)
    }.to_not raise_error
  end

  it 'retry verify' do
    expect {
      thread_running = false

      th = Thread.start {
        thread_running = true
        mysql_stop
        sleep 15
        mysql_start
        thread_running = false
      }

      th.abort_on_exception = true
      sleep 3
      expect(thread_running).to be_true
      ActiveRecord::Base.connection.verify!
      th.join
    }.to_not raise_error
  end

  it 'retry reconnect' do
    expect {
      thread_running = false

      th = Thread.start {
        thread_running = true
        mysql_stop
        sleep 15
        mysql_start
        thread_running = false
      }

      th.abort_on_exception = true
      sleep 3
      expect(thread_running).to be_true
      ActiveRecord::Base.connection.reconnect!
      th.join
    }.to_not raise_error
  end

  it 'disable reconnect' do
    expect {
      begin
        ActiveRecord::Base.enable_retry = false
        expect(Employee.all.length).to eq(300024)
        mysql_restart
        expect(Employee.all.length).to eq(300024)
      ensure
        ActiveRecord::Base.enable_retry = true
      end
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      expect(Employee.all.length).to eq(300024)
      mysql_restart
      expect(Employee.all.length).to eq(300024)
    }.to_not raise_error
  end

  it 'read only (read)' do
    begin
      ActiveRecord::Base.retry_read_only = true

      expect {
        expect(Employee.all.length).to eq(300024)
        mysql_restart
        expect(Employee.all.length).to eq(300024)
      }.to_not raise_error
    ensure
      ActiveRecord::Base.retry_read_only = false
    end
  end

  it 'read only (write)' do
    begin
      ActiveRecord::Base.retry_read_only = true

      expect {
        thread_running = false

        th = Thread.start {
          thread_running = true

          mysql2_error('MySQL server has gone away') do
            emp = Employee.create(
                    :emp_no     => 1,
                    :birth_date => Time.now,
                    :first_name => "' + sleep(15) + '",
                    :last_name  => 'Tiger',
                    :hire_date  => Time.now
                  )
          end

          thread_running = false
        }

        th.abort_on_exception = true
        sleep 3
        expect(thread_running).to be_true
        mysql_restart
        th.join
      }.to raise_error(ActiveRecord::StatementInvalid)
    ensure
      ActiveRecord::Base.retry_read_only = false
    end
  end

  it 'lost connection' do
    expect {
      thread_running = false

      th = Thread.start {
        thread_running = true

        mysql2_error('Lost connection to MySQL server during query') do
          emp = Employee.create(
                  :emp_no     => 1,
                  :birth_date => Time.now,
                  :first_name => "' + sleep(15) + '",
                  :last_name  => 'Tiger',
                  :hire_date  => Time.now
                )
        end

        thread_running = false
      }

      th.abort_on_exception = true
      sleep 3
      expect(thread_running).to be_true
      mysql_restart
      th.join
    }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
