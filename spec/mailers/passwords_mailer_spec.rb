require "rails_helper"

RSpec.describe PasswordsMailer, type: :mailer do
  let(:user) { create(:user, email_address: "test@example.com", password: "password123") }

  describe "#reset" do
    let(:mail) { PasswordsMailer.reset(user) }

    it "sends to the correct address" do
      expect(mail.to).to eq([ "test@example.com" ])
    end

    it "contains reset link" do
      expect(mail.body.encoded).to include("/passwords/")
      expect(mail.body.encoded).to include("/edit")
    end

    it "can be delivered later" do
      expect {
        PasswordsMailer.reset(user).deliver_later
      }.to have_enqueued_mail(PasswordsMailer, :reset)
    end
  end
end
